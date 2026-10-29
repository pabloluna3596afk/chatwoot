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

  it 'reports Payphone disabled for a non-allowlisted account in test mode and forbids its orders' do
    plan = Plan.create!(name: 'Payphone Plan', slug: SecureRandom.hex(4), price_monthly: 19,
                        is_active: true, is_public: true)
    allow(InstallationConfig).to receive(:find_by).and_call_original
    {
      'ENABLE_PAYPHONE' => 'true', 'PAYPHONE_ENVIRONMENT' => 'test', 'PAYPHONE_TEST_ACCOUNT_IDS' => ''
    }.each do |key, value|
      allow(InstallationConfig).to receive(:find_by).with(name: key)
                                                    .and_return(instance_double(InstallationConfig, value: value))
    end

    get path, headers: admin.create_new_auth_token
    expect(response.parsed_body['enabled']).to be(false)
    expect(response.parsed_body['environment']).to eq('test')

    post path, params: { plan_id: plan.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns the real paid-period end and grace access end' do
    plan = Plan.create!(name: 'Payphone Plan', slug: SecureRandom.hex(4), price_monthly: 19,
                        is_active: true, is_public: true)
    period_end = 1.day.ago
    payment = account.payphone_payments.create!(
      user: admin, plan: plan, client_transaction_id: SecureRandom.uuid, amount: 2009,
      amount_without_tax: 1900, amount_with_tax: 0, tax: 0, base_cents: 1900,
      tax_cents: 0, commission_cents: 109
    )
    payment.transition_to!(
      'approved',
      attributes: {
        paid_at: period_end - 30.days, confirmed_at: period_end - 30.days,
        period_start: period_end - 30.days, period_end: period_end
      }
    )
    period_end = payment.reload.period_end
    period_end_json_time = period_end.change(usec: (period_end.usec / 1000) * 1000)

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['renewal_state']).to eq('grace')
    expect(Time.zone.parse(response.parsed_body['period_end'])).to eq(period_end_json_time)
    expect(Time.zone.parse(response.parsed_body['grace_end'])).to eq(period_end_json_time + 3.days)
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

  it 'uses the Confirm token for Cajita when no separate token is configured' do
    plan = Plan.create!(name: 'Payphone Plan', slug: SecureRandom.hex(4), price_monthly: 19,
                        is_active: true, is_public: true)
    configs = {
      'ENABLE_PAYPHONE' => 'true', 'PAYPHONE_ENVIRONMENT' => 'production', 'PAYPHONE_STORE_ID' => 'store-id',
      'PAYPHONE_TOKEN' => 'confirm-bearer-token',
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
    expect(response.parsed_body.dig('box', 'token')).to eq('confirm-bearer-token')
    expect(response.parsed_body.keys).to match_array(
      %w[id plan amount currency status client_transaction_id paid_at period_start period_end created_at box created]
    )

    get path, headers: admin.create_new_auth_token
    expect(response.body).not_to include('confirm-bearer-token')

    post "#{path}/quote", params: { plan_id: plan.id, needs_invoice: false }, headers: admin.create_new_auth_token
    expect(response.body).not_to include('confirm-bearer-token')
  end

  it 'uses the optional Cajita token only in checkout initialization' do
    plan = Plan.create!(name: 'Payphone Plan', slug: SecureRandom.hex(4), price_monthly: 19,
                        is_active: true, is_public: true)
    configs = {
      'ENABLE_PAYPHONE' => 'true', 'PAYPHONE_ENVIRONMENT' => 'production', 'PAYPHONE_STORE_ID' => 'store-id',
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
