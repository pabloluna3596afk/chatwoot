require 'rails_helper'

RSpec.describe 'Captain usage breakdown API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/usage_breakdown" }

  it 'returns grouped usage for the current billing period without sensitive provider data' do
    put_account_on_plan(account)
    period = account.current_usage_period
    period.update!(period_start: 10.days.ago, period_end: 10.days.from_now)
    usage_group_id = SecureRandom.uuid
    2.times do
      AiUsageEvent.create!(account: account, bucket: 'captain_responses', feature: 'faq_generation',
                           model: 'private-model', provider: 'private-provider', usage_group_id: usage_group_id,
                           created_at: 1.day.ago, input_tokens: 10, output_tokens: 20, cost_usd: 5, units: 5, status: 'ok')
    end
    AiUsageEvent.create!(account: account, bucket: 'captain_responses', feature: 'faq_generation', model: 'm',
                         provider: 'p', usage_group_id: SecureRandom.uuid, created_at: 2.months.ago, status: 'ok')

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['buckets']).to include(
      'captain_responses' => [
        a_hash_including('feature' => 'document_faq_generation', 'name' => 'Generate document FAQs',
                         'operations' => 1, 'units' => 5)
      ]
    )
    expect(response.body).not_to match(/cost|model|provider|tokens/i)
  end

  it 'filters the report by bucket' do
    put_account_on_plan(account)
    account.current_usage_period.update!(period_start: 10.days.ago, period_end: 10.days.from_now)
    AiUsageEvent.create!(account: account, bucket: 'internal', feature: 'summary', model: 'm', provider: 'p',
                         usage_group_id: SecureRandom.uuid, created_at: 1.day.ago)

    get path, params: { bucket: 'internal' }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['buckets'].keys).to eq(['internal'])
  end

  it 'rejects agents and invalid buckets' do
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)

    get path, params: { bucket: 'unmapped' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
