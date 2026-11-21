require 'rails_helper'

RSpec.describe Whatsapp::TemplateLibrarySnapshotService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inputs) { [{ 'type' => 'PHONE_NUMBER', 'phone_number' => '+593999999999' }] }
  let(:definition) { { 'library' => { 'template_name' => 'appointment', 'language' => 'es', 'button_inputs' => inputs } } }
  let(:draft) do
    create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config.fetch('business_account_id'),
                                      name: 'my_appointment', language: 'es_EC', definition: definition)
  end
  let(:template) do
    { 'name' => 'appointment', 'language' => 'es', 'body' => 'Tu cita', 'buttons' => [{ 'type' => 'PHONE_NUMBER', 'text' => 'Llamar' }] }
  end
  let(:client) { instance_double(Whatsapp::TemplateManagementService) }

  before do
    allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(client)
    allow(client).to receive(:library).and_return(templates: [template], language_used: 'es', next: nil)
    allow(client).to receive(:templates).and_return([])
  end

  it 'freezes canonical language and authoritative text and posts via the library client exactly once' do
    attempt = Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform
    again = Whatsapp::SubmitTemplateDraftService.new(draft.reload, actor, draft.lock_version).perform
    expect(again.id).to eq(attempt.id)
    expect(attempt.language).to eq('es')
    expect(attempt.snapshot.dig('library_definition', 'library', 'preview', 'body')).to eq('Tu cita')
    expect(client).to receive(:create_from_library).with(library_template_name: 'appointment', name: 'my_appointment', language: 'es',
                                                        category: 'UTILITY', button_inputs: inputs.map(&:deep_symbolize_keys))
                                                 .once.and_return(id: 'meta-library', status: 'PENDING', category: 'UTILITY')
    draft.update!(definition: { 'body' => { 'text' => 'Changed after queueing' } })
    Whatsapp::TemplateSubmissionService.new(attempt).perform
    Whatsapp::TemplateSubmissionService.new(again).perform
    expect(attempt.reload).to have_attributes(status: 'submitted', remote_id: 'meta-library')
  end

  it 'reconciles a timeout using the resolved library components without a second POST or library lookup' do
    attempt = Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform
    allow(client).to receive(:create_from_library).and_raise(Whatsapp::TemplateManagementService::Error, 'meta_unreachable')
    Whatsapp::TemplateSubmissionService.new(attempt).perform
    remote = attempt.snapshot.fetch('reconciliation_payload').merge('name' => draft.name, 'language' => 'es', 'id' => 'meta-library',
                                                                   'status' => 'PENDING', 'category' => 'UTILITY')
    allow(client).to receive(:templates).and_return([remote])
    travel 31.seconds do
      Whatsapp::TemplateSubmissionService.new(attempt).perform
    end
    expect(attempt.reload.status).to eq('submitted')
    expect(client).to have_received(:create_from_library).once
    expect(client).to have_received(:library).once
  end

  it 'does not adopt a different remote body after a timeout' do
    attempt = Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform
    allow(client).to receive(:create_from_library).and_raise(Whatsapp::TemplateManagementService::Error, 'meta_unreachable')
    Whatsapp::TemplateSubmissionService.new(attempt).perform
    allow(client).to receive(:templates).and_return([{ 'name' => draft.name, 'language' => 'es', 'components' => [] }])
    travel 31.seconds do
      Whatsapp::TemplateSubmissionService.new(attempt).perform
    end
    expect(attempt.reload.error_details['code']).to eq('ambiguous_remote_identity')
    expect(client).to have_received(:create_from_library).once
  end

  [[], [{ 'type' => 'PHONE_NUMBER', 'phone_number' => '' }], [{ 'type' => 'PHONE_NUMBER', 'phone_number' => 'invalid' }]].each do |values|
    it "rejects missing or invalid required inputs #{values.inspect} before reserving an attempt" do
      draft.definition['library']['button_inputs'] = values
      draft.save!
      expect { Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform }
        .to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
      expect(draft.submissions).to be_empty
    end
  end

  it 'rejects a missing library identity and a missing destination before any lookup' do
    draft.definition['library']['template_name'] = ''
    expect { Whatsapp::TemplateDraftValidator.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
    draft.assign_attributes(preferred_channel: nil, waba_id: nil)
    expect { Whatsapp::TemplateDraftValidator.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
    expect(client).not_to have_received(:library)
  end

  it 'rejects an unavailable language rather than silently submitting the fallback language' do
    allow(client).to receive(:library).and_return(templates: [template.merge('language' => 'en_US')], language_used: 'en_US', next: nil)
    expect { Whatsapp::TemplateDraftValidator.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
  end

  it 'requires URL inputs and examples for dynamic library buttons' do
    template['buttons'] = [{ 'type' => 'URL', 'text' => 'Abrir', 'url' => 'https://example.com/{{1}}' }]
    draft.definition['library']['button_inputs'] = [{ 'type' => 'URL', 'url' => { 'base_url' => 'https://example.com/' } }]
    expect { Whatsapp::TemplateDraftValidator.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
    draft.definition['library']['button_inputs'][0]['url']['url_suffix_example'] = 'booking'
    expect(Whatsapp::TemplateDraftValidator.new(draft).snapshot!.dig('payload', 'button_inputs')).to eq(draft.definition['library']['button_inputs'])
  end

  it 'rejects a leftover custom media attachment before resolving a library snapshot' do
    draft.media.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png', content_type: 'image/png')
    expect { Whatsapp::TemplateDraftValidator.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
    expect(client).not_to have_received(:library)
  end

  it 'strips remote button IDs and examples from the copyable preview' do
    template['buttons'][0].merge!('id' => 'remote-button', 'example' => ['remote-example'])
    snapshot = Whatsapp::TemplateDraftValidator.new(draft).snapshot!
    expect(snapshot.dig('library_definition', 'library', 'preview', 'buttons')).to eq([{ 'type' => 'PHONE_NUMBER', 'text' => 'Llamar' }])
    expect(Whatsapp::TemplateDraftDefinition.valid?(snapshot.fetch('library_definition'))).to be(true)
  end
end
