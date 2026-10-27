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
end
