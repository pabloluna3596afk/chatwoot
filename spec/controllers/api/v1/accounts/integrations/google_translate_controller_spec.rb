require 'rails_helper'

RSpec.describe 'Google Translate integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:credentials) do
    { type: 'service_account', client_email: 'translator@example.com', private_key: 'private-key-value' }
  end
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/google_translate" }

  describe 'POST /integrations/google_translate' do
    before do
      allow(Integrations::GoogleTranslate::CredentialsValidator).to receive(:valid?).and_return(true)
    end

    it 'stores the project and encrypted credentials without returning the credentials' do
      post url,
           params: { project_id: 'chat-hub-project', credentials: credentials },
           headers: admin.create_new_auth_token,
           as: :json

      hook = account.hooks.find_by!(app_id: 'google_translate')
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('settings', 'project_id')).to eq('chat-hub-project')
      expect(response.body).not_to include('private-key-value')
      expect(hook.settings).to eq('project_id' => 'chat-hub-project')
      expect(JSON.parse(hook.access_token)).to eq(credentials.stringify_keys)
      expect(hook.attributes_before_type_cast['access_token']).not_to include('private-key-value') if Chatwoot.encryption_configured?
    end

    it 'rejects invalid credentials without creating an integration hook' do
      allow(Integrations::GoogleTranslate::CredentialsValidator).to receive(:valid?).and_return(false)

      expect do
        post url,
             params: { project_id: 'chat-hub-project', credentials: credentials },
             headers: admin.create_new_auth_token,
             as: :json
      end.not_to change(Integrations::Hook, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.google_translate.invalid_credentials'))
    end
  end

  describe 'DELETE /integrations/google_translate' do
    it 'disconnects the account hook' do
      hook = create(:integrations_hook, :google_translate, account: account)

      expect do
        delete url, headers: admin.create_new_auth_token, as: :json
      end.to change(Integrations::Hook, :count).by(-1)

      expect(response).to have_http_status(:success)
      expect(Integrations::Hook.exists?(hook.id)).to be false
    end
  end
end
