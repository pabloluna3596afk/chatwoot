require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::Provisioner do
  let(:account) { create(:account, locale: 'es') }
  let(:service) { described_class.new(account: account) }

  it 'reads pending state without writing anything' do
    expect(service.status['results'].values.pluck('status')).to eq(%w[pending pending pending])
    expect(account.reload.calendar_template_preparation).to be_nil
    expect(account.whatsapp_template_drafts).to be_empty
  end

  %w[es en].each do |language|
    it "creates exactly three local UTILITY drafts with the #{language} contract" do
      account.update!(locale: language)
      expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(3)
      expect(service.status['results'].values.pluck('status')).to eq(%w[created created created])
      Calendar::TemplateDefinitions::FUNCTIONS.each do |function, name|
        draft = account.whatsapp_template_drafts.find_by!(name: name)
        definition = Calendar::TemplateDefinitions.definition(function, language)
        expect(draft).to have_attributes(language: language, category: 'UTILITY', parameter_format: 'NAMED', waba_id: nil, preferred_channel_id: nil)
        expect(draft.definition.dig('body', 'text')).to eq(definition.fetch(:body))
        builder = Whatsapp::TemplateComponentsBuilder.new(**draft.definition.deep_symbolize_keys, parameter_format: 'NAMED')
        projection = draft.attributes.merge('id' => 'local-check', 'status' => 'APPROVED', 'components' => builder.components.as_json)
        expect(Calendar::TemplateContract.new(function: function, language: language, template: projection).incompatibility).to be_nil
      end
      expect(account.calendar_template_resources.count).to eq(3)
      expect(account.reload.customer_reminders_enabled).not_to be(true)
    end
  end

  it 'keeps the original language and results on retry without duplicating' do
    first = service.perform
    account.update!(locale: 'en')
    expect { service.perform }.not_to change(WhatsappTemplateDraft, :count)
    expect(service.status).to eq(first)
    expect(service.status['language']).to eq('es')
  end

  it 'keeps new drafts local without choosing even a single available WABA or submitting' do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    service.perform
    expect(account.whatsapp_template_drafts.pluck(:waba_id, :preferred_channel_id)).to eq([[nil, nil]] * 3)
    expect(WhatsappTemplateSubmission.where(account: account)).to be_empty
    expect(service.status['results'].values).to all(include('submitted' => false, 'approved' => false, 'linked' => false))
  end

  it 'reuses a compatible exact homonym without editing its content' do
    definition = Calendar::TemplateDefinitions.definition('confirmation', 'es')
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', parameter_format: 'NAMED',
                                             definition: { body: { text: "#{definition[:body]} Gracias.", examples: definition[:examples] },
                                                           buttons: definition[:buttons].map { |text| { type: 'QUICK_REPLY', text: text } } })
    original = draft.attributes
    expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(2)
    expect(service.status['results']['confirmation']).to include('status' => 'reused', 'draft_id' => draft.id)
    expect(draft.reload.attributes).to eq(original)
  end

  it 'preserves an incompatible homonym and reports a conflict until explicitly retried' do
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', parameter_format: 'POSITIONAL')
    expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(2)
    expect(service.status['results']['confirmation']).to include('status' => 'conflict', 'draft_id' => draft.id)
    expect(draft.reload.definition.dig('body', 'text')).to eq('Tu cita está confirmada.')
    draft.destroy!
    expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(1)
    expect(service.status['results']['confirmation']['status']).to eq('created')
  end

  it 'does not restore prepared drafts after archiving or deletion, even on manual retry' do
    service.perform
    drafts = account.whatsapp_template_drafts.order(:id).to_a
    drafts.first.update!(archived_at: Time.current)
    deleted_id = drafts.last.id
    drafts.last.destroy!
    expect { service.perform }.not_to change(WhatsappTemplateDraft, :count)
    rows = service.status['results'].values
    expect(rows.find { |row| row['draft_id'] == drafts.first.id }['archived']).to be(true)
    expect(rows.find { |row| row['draft_id'] == deleted_id }['draft_exists']).to be(false)
  end

  it 'does not replace an archived homonym predating preparation' do
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', archived_at: Time.current)
    service.perform
    expect(service.status['results']['confirmation']).to include('status' => 'conflict', 'reason' => 'archived_draft', 'draft_id' => draft.id)
    expect(account.whatsapp_template_drafts.where(name: 'cita_confirmacion').count).to eq(1)
  end

  it 'leaves destination selection to the administrator with multiple WABAs' do
    %w[first second].each do |waba|
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      channel.update!(provider_config: channel.provider_config.merge('business_account_id' => waba))
    end
    service.perform
    expect(account.whatsapp_template_drafts.pluck(:waba_id, :preferred_channel_id)).to eq([[nil, nil]] * 3)
  end

  it 'does not duplicate or automatically bind an exact remote homonym' do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [{ 'name' => 'cita_confirmacion', 'language' => 'es', 'status' => 'APPROVED' }])
    service.perform
    expect(service.status['results']['confirmation']).to include('status' => 'conflict', 'reason' => 'remote_template_exists', 'linked' => false)
    expect(account.whatsapp_template_drafts.where(name: 'cita_confirmacion')).to be_empty
  end

  it 'ignores similar names and homonyms in another language or account' do
    create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion_v2')
    create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', language: 'en')
    create(:whatsapp_template_draft, name: 'cita_confirmacion')
    expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(3)
  end

  it 'reports ambiguous exact homonyms without choosing or overwriting either draft' do
    2.times { create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion') }
    expect { service.perform }.to change(WhatsappTemplateDraft, :count).by(2)
    expect(service.status['results']['confirmation']).to include('status' => 'conflict', 'reason' => 'multiple_drafts')
  end

  it 'reports submitted and approved separately from an explicit WABA resource link' do
    service.perform
    draft = account.whatsapp_template_drafts.find_by!(name: 'cita_confirmacion')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    draft.update!(waba_id: channel.provider_config.fetch('business_account_id'), preferred_channel: channel)
    builder = Whatsapp::TemplateComponentsBuilder.new(**draft.definition.deep_symbolize_keys, parameter_format: 'NAMED')
    template = draft.attributes.slice('name', 'language', 'category', 'parameter_format')
                    .merge('id' => 'remote', 'status' => 'APPROVED', 'components' => builder.components.as_json)
    channel.update!(message_templates: [template])
    draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: draft.language,
                              snapshot: { 'name' => draft.name }, payload_digest: 'digest', status: 'submitted', remote_status: 'APPROVED')
    expect(service.status['results']['confirmation']).to include('submitted' => true, 'approved' => true, 'linked' => false)
    Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: channel)
                               .link!(template_name: draft.name, remote_template_id: 'remote', draft: draft)
    expect(service.status['results']['confirmation']).to include('submitted' => true, 'approved' => true, 'linked' => true)
  end

  it 'preserves an existing resource selection without creating a replacement draft' do
    resource = Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es').prepare!(template_name: 'custom_version')
    service.perform
    expect(service.status['results']['confirmation']).to include('status' => 'conflict', 'reason' => 'existing_resource')
    expect(resource.reload.template_name).to eq('custom_version')
    expect(account.whatsapp_template_drafts.where(name: 'cita_confirmacion')).to be_empty
  end

  it 'rolls back the whole preparation on failure so an explicit retry can complete it' do
    allow(service).to receive(:create_draft).with('cancellation', 'es', 'cita_cancelacion').and_raise(StandardError)
    allow(service).to receive(:create_draft).with('confirmation', 'es', 'cita_confirmacion').and_call_original
    expect { service.perform }.to raise_error(StandardError)
    expect(account.reload.calendar_template_preparation).to be_nil
    expect(account.whatsapp_template_drafts).to be_empty
    expect(account.calendar_template_resources).to be_empty
    expect { described_class.new(account: account).perform }.to change(WhatsappTemplateDraft, :count).by(3)
  end
end
