require 'rails_helper'

RSpec.describe Payphone::ConfirmPayment do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:plan) { Plan.create!(name: 'Starter', slug: 'starter', price_monthly: 19, is_active: true, is_public: true) }
  let(:payment) do
    PayphonePayment.create!(account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
                            amount: 2009, amount_without_tax: 1900, amount_with_tax: 0, tax: 0,
                            base_cents: 1900, tax_cents: 0, commission_cents: 109)
  end
  let(:response) do
    { 'statusCode' => 3, 'status' => 'Approved', 'transactionId' => '123',
      'clientTransactionId' => payment.client_transaction_id, 'authorizationCode' => 'AUTH',
      'amount' => payment.amount, 'currency' => 'USD' }
  end
  let(:client) { instance_double(Payphone::FakeClient, confirm: response) }

  it 'activates the plan for 30 days and treats a repeated confirmation as idempotent' do
    mailer = instance_double(PayphoneReceiptMailer)
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(mailer).to receive(:receipt).and_return(delivery)
    allow(delivery).to receive(:deliver_later)
    expect(PayphoneReceiptMailer).to receive(:with).once.and_return(mailer)
    service = described_class.new(payment: payment, transaction_id: '123',
                                  client_transaction_id: payment.client_transaction_id, client: client)

    service.call
    service.call

    expect(payment.reload.status).to eq('approved')
    expect(payment.period_end - payment.period_start).to eq(30.days)
    expect(account.reload.plan_id).to eq(plan.id)
    expect(account.current_usage_period.period_start).to eq(payment.period_start)
    expect(account.current_usage_period.period_end).to eq(payment.period_end)
    expect(client).to have_received(:confirm).once
  end

  it 'does not activate the plan when the confirmed amount differs from the order' do
    response['amount'] += 1
    service = described_class.new(payment: payment, transaction_id: '123',
                                  client_transaction_id: payment.client_transaction_id, client: client)

    expect { service.call }.to raise_error(Payphone::IncongruentConfirmation)
    expect(payment.reload.status).to eq('failed')
    expect(account.reload.plan_id).not_to eq(plan.id)
  end

  it 'extends an early renewal from the current paid period end' do
    previous = PayphonePayment.create!(
      account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
      amount: 2009, amount_without_tax: 1900, amount_with_tax: 0, tax: 0,
      base_cents: 1900, tax_cents: 0, commission_cents: 109
    )
    previous.transition_to!('approved', attributes: {
                              paid_at: 10.days.ago, period_start: 10.days.ago,
                              period_end: 5.days.from_now, confirmed_at: 10.days.ago
                            })
    account.update!(plan: plan, plan_started_at: previous.period_start)

    described_class.new(payment: payment, transaction_id: '123',
                        client_transaction_id: payment.client_transaction_id, client: client).call

    expect(payment.reload.period_start).to be_within(1.second).of(previous.period_end)
    expect(payment.period_end - payment.period_start).to eq(30.days)
  end

  it 'does not activate the plan when Payphone cancels the transaction' do
    response['statusCode'] = 2
    response['status'] = 'Canceled'
    expect(PayphoneReceiptMailer).not_to receive(:with)

    described_class.new(payment: payment, transaction_id: '123',
                        client_transaction_id: payment.client_transaction_id, client: client).call

    expect(payment.reload.status).to eq('cancelled')
    expect(account.reload.plan_id).not_to eq(plan.id)
  end
end
