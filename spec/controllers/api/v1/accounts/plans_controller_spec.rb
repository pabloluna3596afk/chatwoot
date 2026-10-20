require 'rails_helper'

RSpec.describe 'Plan catalog API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/plans" }
  let!(:plan) do
    Plan.create!(name: 'Catalog', slug: 'catalog', description: 'USD 149, promotional USD 119',
                 monthly_messages: 200, storage_mb: 3, max_captain_assistants: 2, max_human_agents: 4,
                 max_inboxes: 5, max_emails_per_day: 50, captain_daily_tests: 10,
                 trial_days: 15, trial_messages: 200, feature_keys: ['automations'])
  end

  it 'requires authentication' do
    get path

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a user from another account' do
    outsider = create(:user, account: create(:account))
    get path, headers: outsider.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows agents and exposes exactly the public contract without consumption writes' do
    headers = agent.create_new_auth_token
    account.update!(plan: plan)

    expect { get path, headers: headers }.not_to change(AccountPlanUsage, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([
                                         {
                                           'id' => plan.id, 'slug' => 'catalog', 'name' => 'Catalog', 'description' => nil,
                                           'display_order' => 0, 'state' => 'available', 'feature_keys' => ['automations'],
                                           'limits' => {
                                             'monthly_responses' => 200, 'storage_bytes' => 3.megabytes, 'assistants' => 2,
                                             'users' => 4, 'inboxes' => 5, 'emails_per_day' => 50, 'tests_per_day' => 10,
                                             'trial_days' => 15, 'trial_responses' => 200
                                           }
                                         }
                                       ])
    expect(response.body).not_to match(/price|USD|promotional|addon|stripe|shopify/i)
  end

  it 'includes coming soon but excludes inactive, private and Developer rows' do
    plan.update!(coming_soon: true)
    Plan.create!(name: 'Inactive', slug: 'inactive', is_active: false)
    Plan.create!(name: 'Private', slug: 'private', is_public: false)
    Plan.create!(name: 'Developer', slug: 'developer', is_public: true)

    get path, headers: agent.create_new_auth_token

    expect(response.parsed_body.pluck('id')).to eq([plan.id])
    expect(response.parsed_body.first['state']).to eq('coming_soon')
  end

  it 'orders by display order and id without using prices' do
    second = Plan.create!(name: 'First', slug: 'first', display_order: -1, price_monthly: 999)
    third = Plan.create!(name: 'Last', slug: 'last', display_order: 0, price_monthly: 0)

    get path, headers: agent.create_new_auth_token

    expect(response.parsed_body.pluck('id')).to eq([second.id, plan.id, third.id])
  end

  it 'preserves zeros rather than substituting unlimited quotas' do
    plan.update!(monthly_messages: 0, storage_mb: 0, captain_daily_tests: 0)

    get path, headers: agent.create_new_auth_token

    expect(response.parsed_body.first['limits']).to include('monthly_responses' => 0, 'storage_bytes' => 0, 'tests_per_day' => 0)
  end

  it 'returns an empty catalog when no plans are visible' do
    plan.update!(is_public: false)

    get path, headers: agent.create_new_auth_token

    expect(response.parsed_body).to eq([])
  end
end
