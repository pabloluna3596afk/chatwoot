require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::AutoLinker do
  let(:account) { create(:account, locale: 'es') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:waba_id) { channel.provider_config.fetch('business_account_id') }
  let(:draft) { create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: waba_id) }
  let(:definition) { Calendar::TemplateDefinitions.definition('confirmation', 'es') }
  let(:template) do
    { 'id' => 'meta-approved', 'name' => draft.name, 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => definition[:body] },
        { 'type' => 'BUTTONS', 'buttons' => definition[:buttons].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
      ] }
  end
  let!(:resource) do
    Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: channel)
                               .prepare!(template_name: draft.name, draft: draft)
  end
  let!(:submission) do
    draft.submissions.create!(account: account, revision: 0, waba_id: waba_id, name: draft.name, language: 'es',
                              snapshot: { 'payload' => {} }, payload_digest: 'digest', status: 'submitted',
                              remote_id: 'meta-approved', remote_status: 'APPROVED')
  end

  before { channel.update!(message_templates: [template]) }

  it 'links an approved compatible draft and is idempotent' do
    expect { described_class.new(account: account, waba_id: waba_id).perform }
      .to change { resource.reload.status }.from('pending').to('linked')
    linked_at = resource.reload.linked_at

    described_class.new(account: account, waba_id: waba_id).perform

    expect(resource.reload).to have_attributes(remote_template_id: 'meta-approved', linked_at: linked_at,
                                               whatsapp_template_draft_id: draft.id)
    expect(Calendar::TemplateDrafts::Status.new(account: account).perform.dig('results', 'confirmation', 'aggregate_state')).to eq('usable')
  end

  it 'records an incompatible approved version with its category reason' do
    channel.update!(message_templates: [template.merge('category' => 'MARKETING')])

    expect { described_class.new(account: account, waba_id: waba_id).perform }
      .to change { resource.reload.status }.from('pending').to('incompatible')
    expect(resource.reload.incompatibility_reason).to eq('category')
  end

  it 'does not replace a version the user already selected' do
    selected = template.merge('id' => 'manual-choice', 'name' => 'manual_choice')
    channel.update!(message_templates: [template, selected])
    Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: channel)
                               .link!(template_name: selected['name'], remote_template_id: selected['id'], draft: draft)

    described_class.new(account: account, waba_id: waba_id).perform

    expect(resource.reload).to have_attributes(status: 'linked', remote_template_id: 'manual-choice', template_name: 'manual_choice')
  end

  it 'continues when the linker fails and logs no template or account data' do
    error = Whatsapp::TemplateComponentsBuilder::Invalid.new('private remote detail')
    linker = instance_double(Calendar::TemplateDrafts::Linker, perform: nil)
    allow(Calendar::TemplateDrafts::Linker).to receive(:new).and_return(linker)
    allow(linker).to receive(:perform).and_raise(error)
    log_line = 'Calendar template auto-link failed (function=confirmation, error=Whatsapp::TemplateComponentsBuilder::Invalid)'
    expect(Rails.logger).to receive(:error).with(log_line)

    expect { described_class.new(account: account, waba_id: waba_id).perform }.not_to raise_error
    expect(submission.reload.remote_status).to eq('APPROVED')
    expect(resource.reload.status).to eq('pending')
  end

  it 'only processes resources and channels for the requested WABA' do
    other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                              validate_provider_config: false)
    other_waba_id = 'another-business-account'
    other_channel.update!(provider_config: other_channel.provider_config.merge('business_account_id' => other_waba_id))
    other_draft = create(:whatsapp_template_draft, account: account, preferred_channel: other_channel, waba_id: other_waba_id)
    other_resource = Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: other_channel)
                                                .prepare!(template_name: other_draft.name, draft: other_draft)
    other_submission = other_draft.submissions.create!(account: account, revision: 0, waba_id: other_waba_id, name: other_draft.name,
                                                       language: 'es', snapshot: { 'payload' => {} }, payload_digest: 'other-digest',
                                                       status: 'submitted', remote_id: 'other-meta', remote_status: 'APPROVED')
    other_template = template.merge('id' => 'other-meta', 'name' => other_draft.name)
    other_channel.update!(message_templates: [other_template])

    described_class.new(account: account, waba_id: waba_id).perform

    expect(resource.reload.status).to eq('linked')
    expect(other_resource.reload.status).to eq('pending')
    expect(other_submission.reload.remote_status).to eq('APPROVED')
  end
end
