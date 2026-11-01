require 'rails_helper'

RSpec.describe Payphone::ExpirePendingPaymentsJob do
  it 'expires pending orders after their fifteen-minute lifetime' do
    account = create(:account)
    user = create(:user)
    plan = Plan.create!(name: 'Starter', slug: 'starter', price_monthly: 19)
    payment = nil

    travel_to(16.minutes.ago) do
      payment = PayphonePayment.create!(
        account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
        amount: 2009, amount_without_tax: 1900, amount_with_tax: 0, tax: 0,
        base_cents: 1900, tax_cents: 0, commission_cents: 109
      )
    end

    described_class.perform_now

    expect(payment.reload.status).to eq('expired')
  end
end
