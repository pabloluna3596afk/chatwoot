require 'rails_helper'

RSpec.describe 'Assigned plan summary', type: :request do
  let(:plan) { Plan.create!(name: 'Assigned', slug: 'assigned', price_monthly: 79) }
  let(:account) { create(:account, plan: plan) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false) }

  it 'adds identity while retaining every existing summary key and value' do
    period = account.current_usage_period

    get "/enterprise/api/v1/accounts/#{account.id}/limits", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('limits', 'plan')).to eq(
      'id' => plan.id, 'slug' => 'assigned', 'name' => 'Assigned', 'price_monthly' => plan.price_monthly.as_json,
      'period_start' => period.period_start.as_json, 'period_end' => period.period_end.as_json
    )
  end

  it 'keeps a null summary for an account without a plan' do
    account.update!(plan: nil)

    get "/enterprise/api/v1/accounts/#{account.id}/limits", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('limits', 'plan')).to be_nil
  end
end
