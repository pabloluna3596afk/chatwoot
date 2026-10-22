require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Inboxes', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:inbox2) { create(:inbox, account: account) }
  let!(:captain_inbox) { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/assistants/:assistant_id/inboxes' do
    context 'when user is authorized' do
      it 'returns a list of inboxes for the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].first[:id]).to eq(captain_inbox.inbox.id)
      end
    end

    context 'when user is unauthorized' do
      it 'returns unauthorized status' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when assistant does not exist' do
      it 'returns not found status' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/999999/inboxes",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account/captain/assistants/:assistant_id/inboxes' do
    let(:valid_params) do
      {
        inbox: {
          inbox_id: inbox2.id
        }
      }
    end

    context 'when user is authorized' do
      it 'creates a new captain inbox' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: valid_params,
               headers: admin.create_new_auth_token
        end.to change(CaptainInbox, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json_response[:id]).to eq(inbox2.id)
      end

      context 'when inbox does not exist' do
        it 'returns not found status' do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: { inbox: { inbox_id: 999_999 } },
               headers: admin.create_new_auth_token

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when params are invalid' do
        it 'returns unprocessable entity status' do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: {},
               headers: admin.create_new_auth_token

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when user is agent' do
      it 'returns unauthorized status' do
        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
             params: valid_params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/captain/assistants/:assistant_id/inboxes/:inbox_id' do
    context 'when user is authorized' do
      it 'deletes the captain inbox' do
        expect do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes/#{inbox.id}",
                 headers: admin.create_new_auth_token
        end.to change(CaptainInbox, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      context 'when captain inbox does not exist' do
        it 'returns not found status' do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes/999999",
                 headers: admin.create_new_auth_token

          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  describe 'audience settings' do
    let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes" }
    let(:rules) do
      { 'tree' => { 'operator' => 'and', 'conditions' => [
        { 'operator' => 'or', 'conditions' => [
          { 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['example.com'] }
        ] }
      ] },
        'phones' => { 'mode' => 'allow', 'list' => ['0991234567'] },
        'channel_ids' => { 'mode' => 'deny', 'list' => ['user'] },
        'emails' => { 'mode' => 'allow', 'list' => ['@example.com'] }, 'contact_scope' => 'new' }
    end

    it 'returns the inherited defaults in index' do
      get url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response[:payload].first).to include(audience_mode: 'inherit', audience_rules: {})
    end

    it 'connects a new inbox with inherited defaults (matrix 17)' do
      post url, params: { inbox: { inbox_id: inbox2.id } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response).to include(audience_mode: 'inherit', audience_rules: {})
    end

    it 'accepts and returns explicit audience settings on create' do
      post url, params: { inbox: { inbox_id: inbox2.id, audience_mode: 'custom', audience_rules: rules } },
                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response).to include(audience_mode: 'custom', audience_rules: rules.deep_symbolize_keys)
      expect(assistant.captain_inboxes.find_by!(inbox_id: inbox2.id).audience_rules).to eq(rules)
    end

    it 'permits a maximum depth tree and all lists without changing appointments' do
      patch "#{url}/#{inbox.id}", params: { inbox: { audience_mode: 'custom', audience_rules: rules } },
                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response).to include(audience_mode: 'custom', audience_rules: rules.deep_symbolize_keys)
      expect(captain_inbox.reload).to have_attributes(audience_rules: rules, appointments_enabled: true)
    end

    it 'preserves rules on a mode-only change and can explicitly clear them' do
      captain_inbox.update!(audience_mode: 'custom', audience_rules: rules)
      patch "#{url}/#{inbox.id}", params: { inbox: { audience_mode: 'everyone' } },
                                  headers: admin.create_new_auth_token, as: :json
      expect(captain_inbox.reload).to have_attributes(audience_mode: 'everyone', audience_rules: rules)

      patch "#{url}/#{inbox.id}", params: { inbox: { audience_mode: 'inherit', audience_rules: {} } },
                                  headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(captain_inbox.reload).to have_attributes(audience_mode: 'inherit', audience_rules: {})
    end

    [
      { audience_mode: 'invalid' }, { audience_mode: nil }, { audience_rules: nil }, { audience_rules: [] },
      { audience_rules: 'invalid' }, { audience_rules: { unknown: true } },
      { audience_rules: { phones: { mode: 'allow', list: [123] } } },
      { audience_rules: { tree: { attribute_key: 'email', filter_operator: 'contains', values: [{ nested: 'value' }] } } },
      { audience_rules: { phones: { mode: 'allow', list: ['1'], unknown: true } } },
      { audience_rules: { phones: { mode: 'allow', list: Array.new(1001, '1') } } },
      { audience_rules: { emails: { mode: 'allow', list: ['a' * 121] } } },
      { audience_rules: { tree: { attribute_key: 'email', filter_operator: 'contains', values: ['a'], unknown: true } } }
    ].each_with_index do |attributes, index|
      it "rejects malformed audience input #{index + 1} with 422 instead of filtering it out" do
        patch "#{url}/#{inbox.id}", params: { inbox: attributes }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(captain_inbox.reload).to have_attributes(audience_mode: 'inherit', audience_rules: {})
      end
    end

    it 'rejects invalid rules before creating a connection' do
      expect do
        post url, params: { inbox: { inbox_id: inbox2.id, audience_rules: { unknown: true } } },
                  headers: admin.create_new_auth_token, as: :json
      end.not_to change(CaptainInbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'forbids agents from changing the audience' do
      patch "#{url}/#{inbox.id}", params: { inbox: { audience_mode: 'everyone', audience_rules: rules } },
                                  headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(captain_inbox.reload).to have_attributes(audience_mode: 'inherit', audience_rules: {})
    end

    it 'forbids agents from connecting with audience settings' do
      post url, params: { inbox: { inbox_id: inbox2.id, audience_mode: 'everyone' } },
                headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(assistant.captain_inboxes.exists?(inbox_id: inbox2.id)).to be(false)
    end

    it 'does not allow moving the connection to another assistant' do
      other_assistant = create(:captain_assistant, account: account)
      patch "#{url}/#{inbox.id}", params: { inbox: { captain_assistant_id: other_assistant.id, audience_mode: 'everyone' } },
                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(captain_inbox.reload.captain_assistant_id).to eq(assistant.id)
    end

    it 'does not update another account connection' do
      other_account = create(:account)
      outsider = create(:user, account: other_account, role: :administrator)
      patch "#{url}/#{inbox.id}", params: { inbox: { audience_mode: 'everyone' } },
                                  headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(captain_inbox.reload.audience_mode).to eq('inherit')
    end
  end
end
