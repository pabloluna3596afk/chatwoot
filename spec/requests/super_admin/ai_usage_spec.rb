require 'rails_helper'

RSpec.describe 'Super Admin AI usage', type: :request do
  let(:account) { create(:account) }
  let(:super_admin) { create(:super_admin) }

  it 'requires a Super Admin session' do
    get '/super_admin/ai_usage'

    expect(response).to have_http_status(:redirect)
  end

  it 'filters summaries to the selected month and company' do
    group_id = SecureRandom.uuid
    2.times do
      AiUsageEvent.create!(
        account: account, bucket: 'captain_responses', feature: 'captain_reply',
        model: 'gpt-6-luna', provider: 'openai', input_tokens: 100, output_tokens: 20,
        usage_group_id: group_id, created_at: Time.zone.local(2026, 10, 10)
      )
    end
    AiUsageEvent.create!(
      account: account, bucket: 'internal', feature: 'summary', model: 'gpt-6-luna',
      provider: 'openai', input_tokens: 100, output_tokens: 20,
      usage_group_id: SecureRandom.uuid, created_at: Time.zone.local(2026, 11, 1)
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_usage', params: { month: '2026-10', account_id: account.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('AI usage', '2', 'gpt-6-luna')
    expect(response.body).not_to include('summary')
  end

  it 'renders the empty state for an account without events' do
    empty_account = create(:account)
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_usage', params: { month: '2026-10', account_id: empty_account.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('No data for this period.')
  end

  it 'alerts when a non-Luna model has no active price' do
    AiUsageEvent.create!(
      account: account, bucket: 'captain_responses', feature: 'captain_reply',
      model: 'gpt-6.1-sol', provider: 'openai', usage_group_id: SecureRandom.uuid,
      created_at: Time.zone.local(2026, 10, 10)
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_usage', params: { month: '2026-10', account_id: account.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('gpt-6.1-sol used', 'No active price is configured for gpt-6.1-sol')
  end

  it 'exports the selected month as CSV' do
    AiUsageEvent.create!(
      account: account, bucket: 'copilot', feature: 'copilot_reply', model: 'gpt-6-luna',
      provider: 'openai', input_tokens: 100, output_tokens: 20,
      usage_group_id: SecureRandom.uuid, created_at: Time.zone.local(2026, 10, 10)
    )
    other_account = create(:account)
    AiUsageEvent.create!(
      account: other_account, bucket: 'copilot', feature: 'other_account_feature', model: 'gpt-6-luna',
      provider: 'openai', input_tokens: 100, output_tokens: 20,
      usage_group_id: SecureRandom.uuid, created_at: Time.zone.local(2026, 10, 10)
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_usage/export', params: { month: '2026-10', account_id: account.id }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    expect(response.body).to include('usage_group_id', 'copilot_reply')
    expect(response.body).not_to include('other_account_feature')
  end
end
