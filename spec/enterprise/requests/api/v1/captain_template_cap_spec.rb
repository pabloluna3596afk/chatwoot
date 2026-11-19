require 'rails_helper'

RSpec.describe 'Captain template cap in account JSON', type: :request do
  let(:account) { create(:account, settings: { captain_template_daily_cap: 73 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.enable_features!('captain_integration') }

  it 'returns the account cap and actual Redis usage to administrators' do
    cap = Captain::TemplateDailyCap.new(account)
    2.times { cap.reserve! }

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['captain_template_cap']).to eq('cap' => 73, 'used' => 2)
  end

  it 'does not disclose the cap to agents' do
    get "/api/v1/accounts/#{account.id}", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key('captain_template_cap')
  end

  it 'returns the updated cap after saving account settings' do
    patch "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token,
                                            params: { captain_template_daily_cap: 80 }, as: :json
    expect(response).to have_http_status(:ok)

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['captain_template_cap']).to eq('cap' => 80, 'used' => 0)
  end

  it 'omits the cap when Captain is disabled' do
    account.disable_features!('captain_integration')

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).not_to have_key('captain_template_cap')
  end
end
