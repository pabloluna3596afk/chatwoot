require 'rails_helper'

RSpec.describe 'Account extras in billing limits', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/enterprise/api/v1/accounts/#{account.id}/limits" }
  let(:plan) { Plan.create!(name: 'Extras', slug: 'extras', monthly_messages: 200, addon_agent_price: 18, addon_inbox_price: 12) }
  let!(:pack) { ExtraPack.create!(bucket: 'captain_responses', units: 500, price_usd: 20) }

  before do
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
  end

  it 'returns current configured prices and only active packs without changing the plans endpoint' do
    account.update!(plan: plan)
    ExtraPack.create!(bucket: 'internal', units: 100, price_usd: 6, active: false)
    plan.update!(addon_agent_price: 19)
    pack.update!(price_usd: 21)

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('limits', 'extras')).to eq(
      'packs' => [{ 'id' => pack.id, 'bucket' => 'captain_responses', 'units' => 500,
                    'price_usd' => 21.0, 'display_order' => 0, 'validity_days' => 90 }],
      'monthly' => { 'extras' => { 'agent' => 19.0, 'bot' => 0.0, 'inbox' => 12.0, 'storage_100mb' => 1.0, 'storage_250mb' => 2.0 } }
    )
  end

  it 'reports only unspent unexpired balances for this account and their earliest expiry' do
    account.update!(plan: plan)
    expiry = 3.days.from_now.change(usec: 0)
    account.grant_extra_balance!(bucket: 'captain_responses', units: 40, source: 'manual', expires_at: expiry)
    account.grant_extra_balance!(bucket: 'captain_responses', units: 60, source: 'manual', expires_at: 5.days.from_now)
    account.grant_extra_balance!(bucket: 'captain_responses', units: 90, source: 'manual', expires_at: 1.day.ago)
    spent = account.grant_extra_balance!(bucket: 'captain_responses', units: 10, source: 'manual', expires_at: 1.day.from_now)
    spent.update!(units_remaining: 0)
    create(:account).grant_extra_balance!(bucket: 'captain_responses', units: 900, source: 'manual', expires_at: 1.day.from_now)

    get path, headers: admin.create_new_auth_token

    balances = response.parsed_body.dig('limits', 'captain')
    expect(balances['responses']).to include('extra_available' => 100, 'extra_next_expiry' => expiry.iso8601(3))
    expect(balances['copilot']).to include('extra_available' => 0, 'extra_next_expiry' => nil)
    expect(balances['internal']).to include('extra_available' => 0, 'extra_next_expiry' => nil)
  end

  it 'returns packs and no monthly offers when there is no assigned plan' do
    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('limits', 'extras', 'packs').pluck('id')).to eq([pack.id])
    expect(response.parsed_body.dig('limits', 'extras', 'monthly')).to eq({})
    expect(response.parsed_body.dig('limits', 'plan')).to be_nil
  end

  it 'preserves unlimited allowances' do
    account.update!(plan: plan)
    plan.update!(limits: { monthly_messages: nil })

    get path, headers: admin.create_new_auth_token

    expect(response.parsed_body.dig('limits', 'captain', 'responses', 'current_available')).to eq(ChatwootApp.max_limit)
    expect(response.parsed_body.dig('limits', 'extras', 'packs').length).to eq(1)
  end

  it 'does not expose own-billing offers on Cloud' do
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)

    get path, headers: admin.create_new_auth_token

    expect(response.parsed_body['limits']).not_to have_key('extras')
  end

  it 'does not expose own-billing offers on Shopify' do
    shopify_account = create(:account, internal_attributes: { billing_provider: 'shopify' })
    shopify_admin = create(:user, account: shopify_account, role: :administrator)

    get "/enterprise/api/v1/accounts/#{shopify_account.id}/limits", headers: shopify_admin.create_new_auth_token

    expect(response.parsed_body['limits']).not_to have_key('extras')
  end

  it 'keeps agent access to usage limits without offering extras' do
    agent = create(:user, account: account, role: :agent)
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['limits']).not_to have_key('extras')
  end

  it 'rejects unauthenticated requests' do
    get path
    expect(response).to have_http_status(:unauthorized)
  end
end
