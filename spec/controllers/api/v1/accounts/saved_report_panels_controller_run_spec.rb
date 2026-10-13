require 'rails_helper'

RSpec.describe Api::V1::Accounts::SavedReportPanelsController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:panel) { create(:saved_report_panel, account: account, created_by: admin) }
  let(:since_value) { Time.utc(2024, 1, 1).to_i }

  before do
    account.enable_features!('report_export')
  end

  [
    { since: '123abc', until: 456 },
    { since: 1.5, until: 456 },
    { since: 456, until: 123 },
    { since: 123 },
    { since: '', until: 456 },
    { since: nil, until: nil },
    { since: 0, until: 367 * 86_400 }
  ].each do |params|
    it "returns 422 for invalid run overrides #{params.inspect}" do
      post "/api/v1/accounts/#{account.id}/saved_report_panels/#{panel.id}/run",
           params: params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end
  end

  it 'validates integer query parameters for exports before building a workbook' do
    get "/api/v1/accounts/#{account.id}/saved_report_panels/#{panel.id}/export",
        params: { since: since_value.to_s, until: (since_value - 1).to_s }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
