require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::CopilotActionItemsController', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :administrator) }
  let(:other_user) { create(:user, account: account, role: :administrator) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: owner) }

  before { account.enable_features!('captain_integration') }

  describe 'GET /api/v1/accounts/{account.id}/captain/copilot_action_items' do
    it 'returns action items for the thread owner' do
      item = CopilotActionItem.create!(
        account: thread.account,
        user: owner,
        copilot_thread: thread,
        action: 'add_label',
        target_type: 'Conversation',
        target_id: 1,
        payload: { label_id: 1 },
        payload_hash: 'payload-hash',
        expires_at: 24.hours.from_now,
        idempotency_key: SecureRandom.uuid
      )

      get "/api/v1/accounts/#{account.id}/captain/copilot_action_items",
          params: { copilot_thread_id: thread.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['id']).to eq(item.id)
    end

    it 'hides a thread from another user in the same account' do
      get "/api/v1/accounts/#{account.id}/captain/copilot_action_items",
          params: { copilot_thread_id: thread.id }, headers: other_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'action item client contract' do
    let(:contact) { create(:contact, account: account) }
    let(:first_label) { create(:label, account: account) }
    let(:second_label) { create(:label, account: account) }
    let(:item) do
      CopilotActionItem.create!(
        account: account,
        user: owner,
        copilot_thread: thread,
        action: 'add_label',
        target_type: 'Contact',
        target_id: contact.id,
        payload: { label_id: first_label.id },
        payload_hash: Digest::SHA256.hexdigest(first_label.id.to_s),
        expires_at: 24.hours.from_now,
        idempotency_key: SecureRandom.uuid
      )
    end

    it 'updates and approves a proposal when each request includes its thread id' do
      patch "/api/v1/accounts/#{account.id}/captain/copilot_action_items/#{item.id}",
            params: { copilot_thread_id: thread.id, payload: { label_id: second_label.id } },
            headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']['label_id']).to eq(second_label.id)

      post "/api/v1/accounts/#{account.id}/captain/copilot_action_items/#{item.id}/approve",
           params: { copilot_thread_id: thread.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('executed')
      expect(contact.reload.label_list).to include(second_label.title)
    end

    it 'rejects a proposal when the request includes its thread id' do
      post "/api/v1/accounts/#{account.id}/captain/copilot_action_items/#{item.id}/reject",
           params: { copilot_thread_id: thread.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('rejected')
    end
  end
end
