require 'rails_helper'

RSpec.describe 'Payphone payments API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/payphone_payments" }

  it 'allows the account administrator to view billing payments' do
    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
  end

  it 'rejects an agent' do
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects an administrator from another account' do
    get path, headers: other_admin.create_new_auth_token

    expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
  end

  it 'requires a session' do
    get path

    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose either configured token in the billing JSON or logs' do
    allow(InstallationConfig).to receive(:find_by).and_call_original
    allow(InstallationConfig).to receive(:find_by).with(name: 'ENABLE_PAYPHONE')
                                                  .and_return(instance_double(InstallationConfig, value: true))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_TOKEN')
                                                  .and_return(instance_double(InstallationConfig, value: 'confirm-secret'))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_BOX_TOKEN')
                                                  .and_return(instance_double(InstallationConfig, value: 'box-secret'))
    log_output = StringIO.new
    allow(Rails.logger).to receive(:info).and_wrap_original do |method, *args|
      log_output.write(args.join)
      method.call(*args)
    end

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('confirm-secret', 'box-secret')
    expect(log_output.string).not_to include('confirm-secret', 'box-secret')
  end

  it 'only returns the Cajita SDK token on checkout and keeps the Confirm token private' do
    plan = Plan.create!(name: 'Payphone Plan', slug: SecureRandom.hex(4), price_monthly: 19,
                        is_active: true, is_public: true)
    configs = {
      'ENABLE_PAYPHONE' => 'true', 'PAYPHONE_STORE_ID' => 'store-id',
      'PAYPHONE_BOX_TOKEN' => 'box-sdk-token', 'PAYPHONE_TOKEN' => 'confirm-bearer-token',
      'PAYPHONE_TAX_RATE' => '15', 'PAYPHONE_CARD_COMMISSION_RATE' => '5.75',
      'PAYPHONE_COMMISSION_ENABLED' => 'true'
    }
    allow(InstallationConfig).to receive(:find_by).and_call_original
    configs.each do |name, value|
      allow(InstallationConfig).to receive(:find_by).with(name: name)
                                                    .and_return(instance_double(InstallationConfig, value: value))
    end

    post path, params: { plan_id: plan.id, needs_invoice: false },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('box', 'token')).to eq('box-sdk-token')
    expect(response.body).not_to include('confirm-bearer-token')
  end

  it 'does not allow an administrator to create a payment for another account' do
    post "/api/v1/accounts/#{other_account.id}/payphone_payments",
         params: { plan_id: 1 }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
  end
end
