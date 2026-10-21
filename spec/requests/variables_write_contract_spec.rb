require 'rails_helper'

RSpec.describe 'Variable write boundaries', type: :request do
  let(:account) { create(:account, appointment_attributes: { 'enabled_keys' => ['total_citas'] }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'total_citas' => 3 }) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'total_citas', attribute_display_type: 'number')
  end

  it 'rejects managed data through the authenticated contacts API' do
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          params: { custom_attributes: { total_citas: 99 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.custom_attributes['total_citas']).to eq(3)
  end

  it 'rejects managed data through prechat without discarding the error as an invalid contact field' do
    patch '/api/v1/widget/contact', params: { website_token: web_widget.website_token, custom_attributes: { total_citas: 99 } },
                                    headers: { 'X-Auth-Token' => token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Read-only variables: total_citas')
    expect(contact.reload.custom_attributes['total_citas']).to eq(3)
  end

  it 'rejects managed data on contact creation' do
    post "/api/v1/accounts/#{account.id}/contacts", params: { name: 'Blocked', custom_attributes: { total_citas: 99 } },
                                                    headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.contacts.find_by(name: 'Blocked')).to be_nil
  end

  it 'rejects deleting managed contact keys' do
    post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/destroy_custom_attributes",
         params: { custom_attributes: ['total_citas'] }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.custom_attributes['total_citas']).to eq(3)
  end

  it 'protects conversation formulas from replacement and implicit removal' do
    create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute', attribute_key: 'computed',
                                         formula: { 'op' => 'count', 'source_attribute_key' => 'amount' })
    conversation = create(:conversation, account: account, contact: contact, custom_attributes: { 'computed' => 3 })
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/custom_attributes",
         params: { custom_attributes: { ordinary: 'value' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.custom_attributes).to eq('computed' => 3)
  end

  it 'keeps the conversation merge contract when a formula already exists' do
    create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute', attribute_key: 'computed',
                                         formula: { 'op' => 'count', 'source_attribute_key' => 'amount' })
    conversation = create(:conversation, account: account, contact: contact, custom_attributes: { 'computed' => 3 })
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/custom_attributes",
         params: { custom_attributes: { ordinary: 'value' }, merge: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.reload.custom_attributes).to eq('computed' => 3, 'ordinary' => 'value')
  end
end
