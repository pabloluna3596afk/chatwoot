require 'rails_helper'

RSpec.describe Whatsapp::TemplateDraftCopyService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:service) { described_class.new(account, actor) }

  it 'copies content and local media while removing nested remote identities and handles' do
    draft = create(:whatsapp_template_draft, account: account, definition: { 'preserved' => { 'buttons' => [
                     { 'position' => 0, 'button' => { 'type' => 'FLOW', 'flow_id' => 'other-waba-id', 'id' => 'remote', 'text' => 'Reservar',
                                                      'nested' => { 'header_handle' => ['source-handle'] } } }
                   ] } })
    draft.media.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png', content_type: 'image/png')
    copy = service.duplicate(draft, 'preferred_channel_id' => channel.id, 'waba_id' => channel.provider_config['business_account_id'])
    expect(copy.definition.to_json).not_to include('other-waba-id', 'source-handle', '"remote"')
    expect(copy.definition.to_json).to include('Reservar')
    expect(copy.media.blob).to eq(draft.media.blob)
    expect(copy).to have_attributes(source_draft_id: draft.id, created_by_id: actor.id, updated_by_id: actor.id)
  end

  it 'keeps named examples aligned with text token order when copying an installed remote template' do
    remote = { 'id' => 'meta-1', 'name' => 'installed', 'language' => 'es', 'category' => 'UTILITY', 'parameter_format' => 'NAMED',
               'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}, tu cita es {{fecha}}.', 'example' => {
                 'body_text_named_params' => [{ 'param_name' => 'fecha', 'example' => 'lunes' }, { 'param_name' => 'nombre', 'example' => 'Ana' }]
               } }] }
    channel.update!(message_templates: [remote])
    copy = service.from_remote(channel, 'meta-1')
    expect(copy.definition.dig('body', 'examples')).to eq(%w[Ana lunes])
    expect(channel.reload.message_templates).to eq([remote])
  end

  it 'keeps library mode in a new version from the immutable submitted snapshot, without remote IDs' do
    definition = { 'library' => { 'template_name' => 'appointment', 'language' => 'es', 'button_inputs' => [],
                                  'preview' => { 'body' => 'Tu cita' } } }
    draft = create(:whatsapp_template_draft, account: account, definition: definition)
    WhatsappTemplateSubmission.create!(whatsapp_template_draft: draft, account: account, remote_id: 'meta-library',
                                       revision: 0, name: draft.name, language: 'es', payload_digest: 'digest',
                                       waba_id: channel.provider_config.fetch('business_account_id'),
                                       snapshot: { 'library_definition' => definition })
    channel.update!(message_templates: [{ 'id' => 'meta-library', 'name' => 'installed', 'language' => 'es', 'category' => 'UTILITY' }])
    copy = service.from_remote(channel, 'meta-library')
    expect(copy.definition).to eq(definition)
    expect(copy.submissions).to be_empty
    expect(copy.definition.to_json).not_to include('meta-library')
    expect(copy.source_remote_id).to eq('meta-library')
  end
end
