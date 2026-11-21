require 'rails_helper'

RSpec.describe Whatsapp::TemplateDraftSourceService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:service) { described_class.new(account, actor, channel) }

  Whatsapp::BotTemplateBlueprintService::BLUEPRINTS.each_key do |id|
    it "submits #{id} through the common pipeline with the legacy body, examples and buttons" do
      draft = service.from_blueprint(id)
      legacy = Whatsapp::BotTemplateBlueprintService.new(channel)
      expected = legacy.send(:build_request_body, Whatsapp::BotTemplateBlueprintService::BLUEPRINTS.fetch(id)).deep_stringify_keys
      attempt = Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform
      expect(attempt.snapshot.fetch('payload')).to eq(expected.merge('parameter_format' => 'POSITIONAL'))
      expect(Whatsapp::SubmitTemplateDraftJob).to have_been_enqueued.with(attempt.id)
      expect(draft).to have_attributes(language: 'es', parameter_format: 'POSITIONAL', created_by: actor)
    end
  end

  it 'increments the suffix for active local and remote names in the same WABA and language' do
    first = service.from_blueprint('palu_reenganche')
    channel.update!(message_templates: [{ 'name' => 'palu_reenganche_2', 'language' => 'es' }])
    expect(service.from_blueprint('palu_reenganche').name).to eq('palu_reenganche_3')
    first.update!(archived_at: Time.current)
    expect(service.from_blueprint('palu_reenganche').name).to eq('palu_reenganche')
  end

  it 'creates without a channel and rejects an unknown blueprint' do
    local = described_class.new(account, actor)
    expect(local.from_blueprint('palu_reenganche').preferred_channel).to be_nil
    expect(local.from_blueprint('palu_reenganche').name).to eq('palu_reenganche_2')
    expect { local.from_blueprint('missing') }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid) do |error|
      expect(error.code).to eq('unknown_blueprint')
    end
  end

  it 'saves incomplete library button values without HTTP or editable text' do
    draft = service.from_library(library_template_name: 'appointment', name: 'appointment', language: 'es', category: 'UTILITY',
                                 button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '' }])
    expect(draft.definition).to eq('library' => { 'template_name' => 'appointment', 'language' => 'es',
                                                 'button_inputs' => [{ 'type' => 'PHONE_NUMBER', 'phone_number' => '' }] })
    expect(draft.submissions).to be_empty
  end
end
