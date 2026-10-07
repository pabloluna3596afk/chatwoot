require 'rails_helper'

RSpec.describe 'Conversation WhatsApp flows', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/whatsapp_flows" }
  let(:headers) { agent.create_new_auth_token }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, created_at: 1.minute.ago)
    WhatsappFlowPublication.create!(whatsapp_flow: flow, account: account, waba_id: channel.provider_config['business_account_id'],
                                    status: 'published', meta_flow_id: '123456', published_at: Time.current)
  end

  it 'lets an inbox agent list and send one currently published Flow' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([flow.id])
    expect(response.parsed_body['payload'].first).to include('status' => 'published', 'can_send' => true, 'unpublished_changes' => false)
    expect { post url, params: { whatsapp_flow_id: flow.id }, headers: headers, as: :json }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(conversation.messages.last.additional_attributes.dig('whatsapp_flow', 'id')).to eq(flow.id)
  end

  it 'includes every local Flow using only the current WABA publication without exposing credentials' do
    draft = create(:whatsapp_flow, account: account)
    other_waba = create(:whatsapp_flow, account: account)
    WhatsappFlowPublication.create!(whatsapp_flow: draft, account: account, waba_id: channel.provider_config['business_account_id'],
                                    status: 'draft', meta_flow_id: '234567')
    WhatsappFlowPublication.create!(whatsapp_flow: other_waba, account: account, waba_id: '999999',
                                    status: 'published', meta_flow_id: '345678', published_at: Time.current)
    create(:whatsapp_flow)

    get url, headers: headers
    rows = response.parsed_body['payload'].index_by { |row| row['id'] }
    expect(rows.keys).to contain_exactly(flow.id, draft.id, other_waba.id)
    expect(rows[draft.id]).to include('status' => 'draft', 'can_send' => false)
    expect(rows[other_waba.id]).to include('status' => 'none', 'can_send' => false)
    expect(rows[flow.id].keys).to contain_exactly('id', 'name', 'categories', 'status', 'unpublished_changes', 'screens', 'can_send')
  end

  it 'lists changes needing publication and keeps their send endpoint blocked' do
    flow.update!(name: 'Updated Flow')
    get url, headers: headers
    expect(response.parsed_body['payload'].first).to include('status' => 'published', 'unpublished_changes' => true, 'can_send' => false)
    expect { post url, params: { whatsapp_flow_id: flow.id }, headers: headers, as: :json }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'allows consulting the catalog outside the messaging window with sending disabled' do
    conversation.messages.incoming.update_all(created_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('can_reply' => false)
    expect(response.parsed_body['payload'].first).to include('status' => 'published', 'can_send' => false)
  end

  it 'denies an agent without access and another account' do
    outsider = create(:user, account: account, role: :agent)
    post url, params: { whatsapp_flow_id: flow.id }, headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    foreign = create(:user)
    get url, headers: foreign.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
  end

  it 'returns 422 for malformed ids/texts, missing publications and a closed window' do
    [{ whatsapp_flow_id: flow.id.to_s }, { whatsapp_flow_id: flow.id, body: [] },
     { whatsapp_flow_id: flow.id, cta: 'x' * 21 }, { whatsapp_flow_id: flow.id + 100 }].each do |payload|
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    conversation.messages.incoming.update_all(created_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    post url, params: { whatsapp_flow_id: flow.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
