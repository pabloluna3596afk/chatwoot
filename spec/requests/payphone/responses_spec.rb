require 'rails_helper'

RSpec.describe 'Payphone response URL' do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:plan) { Plan.create!(name: 'Starter', slug: 'starter', price_monthly: 19, is_active: true, is_public: true) }
  let(:payment) do
    PayphonePayment.create!(account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
                            amount: 2009, amount_without_tax: 1900, amount_with_tax: 0, tax: 0,
                            base_cents: 1900, tax_cents: 0, commission_cents: 109)
  end

  it 'is reachable without a signed-in user and rejects malformed parameters' do
    get '/payphone/response', params: { id: 'abc', clientTransactionId: 'nope' }

    expect(response).to have_http_status(:bad_request)
  end

  it 'answers 404 for an unknown client transaction without requiring authentication' do
    get '/payphone/response', params: { id: '123', clientTransactionId: SecureRandom.uuid }

    expect(response).to have_http_status(:not_found)
  end

  it 'redirects to billing with the payment status after confirming' do
    confirmation = instance_double(Payphone::ConfirmPayment, call: payment)
    allow(Payphone::ConfirmPayment).to receive(:new).and_return(confirmation)

    get '/payphone/response', params: { id: '123', clientTransactionId: payment.client_transaction_id }

    expect(response).to redirect_to("/app/accounts/#{account.id}/settings/billing?payphone=#{payment.status}")
  end
end
