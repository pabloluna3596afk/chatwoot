require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageWhatsappCloudService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+593991234567') }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '593991234567') }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:outgoing) do
    create(:message, conversation: conversation, account: channel.account, inbox: channel.inbox, message_type: :outgoing,
                     additional_attributes: { whatsapp_flow: { id: 1, name: 'Datos', fields: [
                       { type: 'short_text', key: 'nombre', save_to: { target: 'contact.name' } }
                     ] } })
  end
  let(:token) { Whatsapp::Flows::ResponseToken.generate(outgoing) }
  let(:params) do
    { object: 'whatsapp_business_account', entry: [{ changes: [{ value: {
      contacts: [{ profile: { name: 'Original' }, wa_id: '593991234567' }],
      messages: [{ from: '593991234567', id: 'wamid.saved-flow', timestamp: Time.current.to_i.to_s, type: 'interactive',
                   interactive: { type: 'nfm_reply', nfm_reply: { response_json: { flow_token: token, nombre: 'Nuevo nombre' }.to_json } } }]
    } }] }] }.with_indifferent_access
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'updates the contact and creates one private note for a repeated webhook, without persisting the token' do
    outgoing
    2.times { described_class.new(inbox: channel.inbox, params: params).perform }
    expect(contact.reload.name).to eq('Nuevo nombre')
    expect(conversation.messages.where(private: true).count).to eq(1)
    incoming = channel.inbox.messages.find_by!(source_id: 'wamid.saved-flow')
    expect(incoming.content_attributes['whatsapp_flow_response']).to eq('nombre' => 'Nuevo nombre')
  end

  it 'keeps unknown tokens as text only' do
    invalid_params = params.deep_dup
    invalid_params[:entry][0][:changes][0][:value][:messages][0][:interactive][:nfm_reply][:response_json] =
      { flow_token: 'unknown', nombre: 'Nuevo nombre' }.to_json
    described_class.new(inbox: channel.inbox, params: invalid_params).perform
    expect(contact.reload.name).not_to eq('Nuevo nombre')
    expect(channel.inbox.messages.where(private: true)).to be_empty
    expect(channel.inbox.messages.find_by!(source_id: 'wamid.saved-flow').content).to include('Nuevo nombre')
  end
end
