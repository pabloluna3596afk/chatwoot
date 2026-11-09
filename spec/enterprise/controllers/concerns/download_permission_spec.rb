require 'rails_helper'

RSpec.describe 'Blocked download audits', type: :request do
  it 'records the account, actor, feature, endpoint and IP alongside the warning' do
    account = create(:account)
    admin = create(:user, account: account, role: :administrator)
    account.disable_features!('customer_data_export')
    allow(Rails.logger).to receive(:warn)

    expect do
      post "/api/v1/accounts/#{account.id}/contacts/export", headers: admin.create_new_auth_token, as: :json
    end.to change { account.associated_audits.where(action: 'download_blocked').count }.by(1)

    audit = account.associated_audits.find_by!(action: 'download_blocked')
    expect(response).to have_http_status(:forbidden)
    expect(audit.user).to eq(admin)
    expect(audit.audited_changes).to include('feature' => 'customer_data_export', 'path' => "/api/v1/accounts/#{account.id}/contacts/export")
    expect(audit.remote_address).to be_present
    expect(audit.request_uuid).to be_present
    expect(Rails.logger).to have_received(:warn).with(/DownloadBlocked.*customer_data_export/)
  end
end
