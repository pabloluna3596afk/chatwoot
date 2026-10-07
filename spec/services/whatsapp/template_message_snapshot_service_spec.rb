require 'rails_helper'

RSpec.describe Whatsapp::TemplateMessageSnapshotService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:header) { { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'For {{1}}' } }
  let(:entry) do
    { 'name' => 'appointment', 'language' => 'en', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [header, { 'type' => 'BODY', 'text' => 'Hello {{1}}' }, { 'type' => 'FOOTER', 'text' => 'Thank you' },
                       { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Confirm' },
                                                            { 'type' => 'URL', 'text' => 'Location', 'url' => 'https://example.com/{{1}}' },
                                                            { 'type' => 'FLOW', 'text' => 'Open Flow', 'flow_id' => 'internal-id' }] }] }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false, message_templates: [entry])
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:reference) do
    { 'name' => 'appointment', 'language' => 'en', 'category' => 'UTILITY', 'content_mode' => 'raw_template',
      'processed_params' => { 'header' => { '1' => '{{ contact.name }}' }, 'body' => { '1' => 'Ana' },
                              'buttons' => [{ 'type' => 'flow', 'flow_token' => 'private-test-value' }] } }
  end

  it 'stores the manual picker snapshot after Liquid, without reinterpreting parameter values' do
    message = Messages::MessageBuilder.new(user, conversation, { content: 'Hello {{1}}', template_params: reference }).perform
    snapshot = message.reload.content_attributes.fetch('whatsapp_template')

    expect(snapshot).to include('name' => 'appointment', 'category' => 'UTILITY', 'footer' => 'Thank you')
    expect(snapshot['header']).to eq('format' => 'TEXT', 'text' => "For #{conversation.contact.name}")
    expect(snapshot['buttons']).to eq([{ 'type' => 'QUICK_REPLY', 'text' => 'Confirm' }, { 'type' => 'URL', 'text' => 'Location' },
                                       { 'type' => 'FLOW', 'text' => 'Open Flow' }])
    expect(snapshot.to_json).not_to include('flow_token', 'internal-id', 'private-test-value')
    channel.update!(message_templates: [])
    expect(message.reload.content_attributes['whatsapp_template']).to eq(snapshot)
  end

  it 'stores media type alongside the existing header attachment' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('image'), filename: 'header.png', content_type: 'image/png', metadata: { 'account_id' => account.id }
    )
    header.replace('type' => 'HEADER', 'format' => 'IMAGE')
    channel.update!(message_templates: [entry])
    reference['processed_params']['header'] = { 'media_blob' => blob.signed_id, 'media_type' => 'image' }
    message = Messages::MessageBuilder.new(user, conversation, { content: 'Hello Ana', template_params: reference }).perform

    expect(message.reload.content_attributes.dig('whatsapp_template', 'header')).to eq('format' => 'IMAGE')
    expect(message.attachments.first.file.blob).to eq(blob)
  end

  it 'stores the snapshot through the real automation action and keeps its source metadata' do
    rule = create(:automation_rule, account: account, actions: [
                    { action_name: 'send_whatsapp_template', action_params: [reference.merge('inbox_id' => inbox.id)] }
                  ])
    AutomationRules::ActionService.new(rule, account, conversation).perform
    message = conversation.messages.outgoing.where(private: false).last

    expect(message.content_attributes.dig('whatsapp_template', 'name')).to eq('appointment')
    expect(message.content_attributes.dig('whatsapp_template', 'header', 'text')).to eq("For #{conversation.contact.name}")
    expect(message.content_attributes['automation_rule_id']).to eq(rule.id)
  end

  it 'does not add a snapshot when the historical catalog entry is unavailable' do
    reference['name'] = 'removed'
    message = Messages::MessageBuilder.new(user, conversation, { content: 'Hello Ana', template_params: reference }).perform

    expect(message.reload.content_attributes).not_to have_key('whatsapp_template')
  end
end
