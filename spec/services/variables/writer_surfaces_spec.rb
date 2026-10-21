require 'rails_helper'

RSpec.describe Variables::Writer do
  let(:account) { create(:account, appointment_attributes: { 'enabled_keys' => ['total_citas'] }) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'total_citas' => 3 }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'total_citas', attribute_display_type: 'number')
  end

  it 'prevents stale actions from overwriting managed Calendar values' do
    ActionService.new(conversation).update_contact_custom_attribute({ attribute_key: 'total_citas', value: 99 })
    expect(contact.reload.custom_attributes['total_citas']).to eq(3)
  end

  it 'renders multi_list entries through the shared resolver before writing' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'interests', attribute_display_type: 'multi_list', attribute_values: ['VIP'])
    contact.update!(name: 'VIP')
    ActionService.new(conversation).update_contact_custom_attribute({ attribute_key: 'interests', value: ['{{ contact.name }}'] })
    expect(contact.reload.custom_attributes['interests']).to eq(['VIP'])
  end

  it 'rejects a stale Flow snapshot after Calendar takes ownership' do
    fields = [{ 'type' => 'short_text', 'input' => 'number', 'key' => 'count', 'save_to' => { 'target' => 'contact.custom_attribute.total_citas' } }]
    outgoing = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing,
                                additional_attributes: { 'whatsapp_flow' => { 'name' => 'Count', 'fields' => fields } })
    incoming = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming)
    payload = { 'flow_token' => Whatsapp::Flows::ResponseToken.generate(outgoing), 'count' => '99' }
    Whatsapp::Flows::SaveResponseService.new(incoming, payload).perform
    expect(contact.reload.custom_attributes['total_citas']).to eq(3)
    expect(incoming.reload.content_attributes['whatsapp_flow_saved']).to be(true)
  end
end
