require 'rails_helper'

RSpec.describe PayphonePayment do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:plan) { Plan.create!(name: 'Starter', slug: 'starter') }
  let(:attributes) do
    {
      account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
      amount: 2009, amount_without_tax: 1900, amount_with_tax: 0, tax: 0,
      base_cents: 1900, tax_cents: 0, commission_cents: 109
    }
  end

  it 'stores pending payment snapshots with an initial audit entry' do
    payment = described_class.create!(attributes)

    expect(payment.status).to eq('pending')
    expect(payment.status_history.last).to include('to' => 'pending')
  end

  it 'requires complete billing details when an invoice is requested' do
    payment = described_class.new(attributes.merge(needs_invoice: true))

    expect(payment).not_to be_valid
    expect(payment.errors[:billing_tax_id]).to be_present
  end

  it 'clears billing details when no invoice is requested' do
    payment = described_class.create!(attributes.merge(billing_name: 'Ignored name'))

    expect(payment.billing_name).to be_nil
  end

  it 'rejects a Payphone response containing non-allowlisted fields' do
    payment = described_class.new(attributes.merge(raw_response: { 'cardNumber' => '4111111111111111' }))

    expect(payment).not_to be_valid
    expect(payment.errors[:raw_response]).to be_present
  end

  it 'records valid state transitions and refuses transitions from terminal states' do
    payment = described_class.create!(attributes)
    payment.transition_to!('failed', attributes: { raw_response: { 'status' => 'rejected' } })

    expect(payment.status_history.last).to include('from' => 'pending', 'to' => 'failed')
    expect { payment.transition_to!('approved') }.to raise_error(ArgumentError)
  end

  it 'requires a paid period before a pending payment can be approved' do
    payment = described_class.create!(attributes)

    approval_attributes = {
      paid_at: Time.current,
      period_start: Time.current,
      period_end: 30.days.from_now,
      confirmed_at: Time.current,
      raw_response: { 'status' => 'approved' }
    }
    payment.transition_to!('approved', attributes: approval_attributes)

    expect(payment.status).to eq('approved')
    expect(payment.period_end).to be > payment.period_start
  end

  it 'keeps purchase and billing snapshots immutable after creation' do
    payment = described_class.create!(attributes)
    payment.amount = 100

    expect(payment).not_to be_valid
    expect(payment.errors[:base].join).to include('payment snapshot is immutable')
  end

  it 'encrypts the reserved card token field before persistence' do
    payment = described_class.create!(attributes.merge(card_token: 'card-token-value'))

    expect(payment.reload[:card_token]).not_to include('card-token-value')
    expect(payment.card_token).to eq('card-token-value')
  end
end
