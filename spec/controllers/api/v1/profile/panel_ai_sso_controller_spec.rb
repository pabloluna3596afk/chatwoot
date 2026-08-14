require 'rails_helper'

RSpec.describe 'Profile Panel AI SSO API', type: :request do
  let(:account) { create(:account) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PANEL_AI_PUBLIC_URL', '').and_return('https://ainbox.example.com')
  end

  describe 'POST /api/v1/profile/panel_ai_sso' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post '/api/v1/profile/panel_ai_sso', params: { account_id: account.id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns forbidden' do
        post '/api/v1/profile/panel_ai_sso',
             params: { account_id: account.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when it is an administrator' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'returns an SSO URL' do
        post '/api/v1/profile/panel_ai_sso',
             params: { account_id: account.id },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['url']).to include('https://ainbox.example.com/login/sso?email=')
        expect(body['url']).to include('sso_auth_token=')
      end
    end
  end
end
