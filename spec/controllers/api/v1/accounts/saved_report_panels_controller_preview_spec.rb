require 'rails_helper'

RSpec.describe 'Saved report panels preview', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:params) do
    {
      saved_report_panel: {
        name: 'Draft panel', date_preset: 'last_7_days', filters: [],
        widgets: [{ id: 'draft_metric', type: 'metric', metric: 'conversations_count' }]
      }
    }
  end

  it 'runs the current configuration for an administrator without saving a panel' do
    headers = admin.create_new_auth_token
    expect do
      post "/api/v1/accounts/#{account.id}/saved_report_panels/preview",
           params: params, headers: headers, as: :json
    end.not_to change(SavedReportPanel, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['panel_id']).to be_nil
    expect(response.parsed_body['widgets'].first).to include('id' => 'draft_metric', 'value' => 0)
  end

  it 'rejects an agent without saving a panel' do
    headers = agent.create_new_auth_token
    expect do
      post "/api/v1/accounts/#{account.id}/saved_report_panels/preview",
           params: params, headers: headers, as: :json
    end.not_to change(SavedReportPanel, :count)

    expect(response).to have_http_status(:forbidden)
  end
end
