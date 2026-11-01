require 'rails_helper'

RSpec.describe 'AI usage API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/ai_usage" }

  it 'returns per day and bucket counts to admins without cost data' do
    put_account_on_plan(account)
    account.current_usage_period.update!(period_start: 10.days.ago, period_end: 20.days.from_now)
    usage_group_id = SecureRandom.uuid
    %w[captain_responses copilot].each do |bucket|
      AiUsageEvent.create!(account: account, bucket: bucket, feature: 'reply', model: 'private-model',
                           provider: 'internal', usage_group_id: usage_group_id, created_at: 1.day.ago,
                           input_tokens: 100, output_tokens: 50, cost_usd: 1)
    end
    AiUsageEvent.create!(account: account, bucket: 'captain_responses', feature: 'reply', model: 'private-model',
                         provider: 'internal', usage_group_id: usage_group_id, created_at: 1.day.ago,
                         input_tokens: 50, output_tokens: 25, cost_usd: 1)
    AiUsageEvent.create!(account: other_account, bucket: 'internal', feature: 'reply', model: 'private-model',
                         provider: 'internal', usage_group_id: SecureRandom.uuid, created_at: 1.day.ago)

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['daily']).to contain_exactly(
      a_hash_including('bucket' => 'captain_responses', 'messages' => 1),
      a_hash_including('bucket' => 'copilot', 'messages' => 1)
    )
    expect(response.body).not_to match(/token|cost|model|provider/i)
  end

  it 'does not count failed attempts as used messages' do
    put_account_on_plan(account)
    account.current_usage_period.update!(period_start: 10.days.ago, period_end: 20.days.from_now)
    AiUsageEvent.create!(account: account, bucket: 'internal', feature: 'summarize', model: 'private-model',
                         provider: 'internal', usage_group_id: SecureRandom.uuid, created_at: 1.day.ago, status: 'ok')
    AiUsageEvent.create!(account: account, bucket: 'internal', feature: 'summarize', model: 'private-model',
                         provider: 'internal', usage_group_id: SecureRandom.uuid, created_at: 1.day.ago, status: 'error')

    get path, headers: admin.create_new_auth_token

    expect(response.parsed_body['daily']).to contain_exactly(a_hash_including('bucket' => 'internal', 'messages' => 1))
  end

  it 'rejects agents because billing settings are administrator-only' do
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects users from another account' do
    get path, headers: other_admin.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
      .or have_http_status(:forbidden)
      .or have_http_status(:not_found)
  end

  it 'returns an empty period for a new account' do
    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'daily' => [], 'period_start' => nil, 'period_end' => nil,
      'bag_modes' => { 'captain_responses' => 'unlimited', 'copilot' => 'shared', 'internal' => 'unlimited' }
    )
  end

  it 'returns the lazily opened period for an older account on a plan' do
    put_account_on_plan(account, monthly_messages: 100)
    account.account_plan_usages.destroy_all

    get path, headers: admin.create_new_auth_token

    usage_period = account.account_plan_usages.open.sole
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'period_start' => usage_period.period_start.as_json,
      'period_end' => usage_period.period_end.as_json
    )
  end

  it 'returns the bag modes when an account period exists' do
    AccountPlanUsage.create!(account: account, period_start: 10.days.ago, period_end: 20.days.from_now)

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['bag_modes']).to include(
      'captain_responses' => 'unlimited', 'copilot' => 'shared', 'internal' => 'unlimited'
    )
  end

  it 'marks zero-limit bags as not included' do
    account.update!(limits: { 'captain_responses' => 0, 'captain_copilot' => 0, 'captain_internal' => 0 })

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['bag_modes']).to eq(
      'captain_responses' => 'not_included', 'copilot' => 'not_included', 'internal' => 'not_included'
    )
  end

  it 'returns a translated access denied message to agents' do
    account.update!(locale: 'es')
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('No tienes permiso para acceder a este recurso.')
  end
end
