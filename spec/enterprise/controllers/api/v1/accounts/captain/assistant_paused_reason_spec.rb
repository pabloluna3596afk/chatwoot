require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants paused_reason', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:assistant) { create(:captain_assistant, account: account) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def remove_installation_key
    allow(Llm::Config).to receive(:api_key_configured?).and_call_original
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
  end

  it 'has no paused reason while the assistant can answer' do
    get "/api/v1/accounts/#{account.id}/captain/assistants", headers: admin.create_new_auth_token, as: :json

    expect(json_response[:payload].first).to include(id: assistant.id, paused_reason: nil)
  end

  it 'reports a missing AI key in the list and in the single assistant' do
    remove_installation_key

    get "/api/v1/accounts/#{account.id}/captain/assistants", headers: admin.create_new_auth_token, as: :json
    expect(json_response[:payload].first[:paused_reason]).to eq('missing_key')

    get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}", headers: admin.create_new_auth_token, as: :json
    expect(json_response[:paused_reason]).to eq('missing_key')
  end

  it 'reports exhausted responses' do
    put_account_on_plan(account, monthly_messages: 100, used: 100)

    get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}", headers: admin.create_new_auth_token, as: :json

    expect(json_response[:paused_reason]).to eq('quota_exhausted')
  end
end
