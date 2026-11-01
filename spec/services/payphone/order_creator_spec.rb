require 'rails_helper'

RSpec.describe Payphone::OrderCreator do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:plan) { Plan.create!(name: 'Starter', slug: 'starter', price_monthly: 19, is_active: true, is_public: true) }

  before do
    allow(InstallationConfig).to receive(:find_by).and_call_original
    allow(InstallationConfig).to receive(:find_by).with(name: 'ENABLE_PAYPHONE')
                                                  .and_return(instance_double(InstallationConfig, value: true))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_TAX_RATE')
                                                  .and_return(instance_double(InstallationConfig, value: '15'))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_CARD_COMMISSION_RATE')
                                                  .and_return(instance_double(InstallationConfig, value: '5.75'))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_COMMISSION_ENABLED')
                                                  .and_return(instance_double(InstallationConfig, value: true))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_ENVIRONMENT')
                                                  .and_return(instance_double(InstallationConfig, value: 'test'))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_TEST_ACCOUNT_IDS')
                                                  .and_return(instance_double(InstallationConfig, value: account.id.to_s))
  end

  it 'prices from the plan and reuses the open order when the browser retries' do
    params = { plan_id: plan.id, needs_invoice: false, amount: 1 }

    first_payment, created = described_class.new(account: account, user: user, params: params).call
    second_payment, retried = described_class.new(account: account, user: user, params: params).call

    expect(created).to be(true)
    expect(retried).to be(false)
    expect(second_payment.id).to eq(first_payment.id)
    expect(first_payment.amount).to eq(2009)
  end

  it 'blocks Payphone checkout while Stripe has an active subscription' do
    account.update!(custom_attributes: { 'stripe_customer_id' => 'cus_123', 'subscription_status' => 'active' })

    expect do
      described_class.new(account: account, user: user, params: { plan_id: plan.id }).call
    end.to raise_error(Payphone::StripeSubscriptionActive)
  end

  it 'blocks order creation for an account outside the test allowlist and reads changes immediately' do
    config = instance_double(InstallationConfig, value: '')
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_TEST_ACCOUNT_IDS').and_return(config)
    expect { described_class.new(account: account, user: user, params: { plan_id: plan.id, needs_invoice: false }).call }
      .to raise_error(Payphone::AccountNotAllowed)

    allow(config).to receive(:value).and_return(account.id.to_s)
    expect { described_class.new(account: account, user: user, params: { plan_id: plan.id, needs_invoice: false }).call }
      .not_to raise_error
  end

  it 'allows every account in production regardless of the test allowlist' do
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_ENVIRONMENT')
                                                  .and_return(instance_double(InstallationConfig, value: 'production'))
    allow(InstallationConfig).to receive(:find_by).with(name: 'PAYPHONE_TEST_ACCOUNT_IDS')
                                                  .and_return(instance_double(InstallationConfig, value: ''))

    expect { described_class.new(account: account, user: user, params: { plan_id: plan.id, needs_invoice: false }).call }
      .not_to raise_error
  end
end
