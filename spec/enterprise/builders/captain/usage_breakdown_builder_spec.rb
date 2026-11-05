require 'rails_helper'

RSpec.describe Captain::UsageBreakdownBuilder do
  let(:account) { create(:account) }
  let(:period) do
    AccountPlanUsage.create!(account: account, period_start: 10.days.ago, period_end: 10.days.from_now)
  end

  it 'groups feature variants, counts distinct operations, and uses the maximum units per group' do
    rewrite_group_id = SecureRandom.uuid
    faq_group_id = SecureRandom.uuid
    latest_rewrite_event_at = 1.day.ago
    latest_faq_event_at = 1.hour.ago
    [
      ['professional', rewrite_group_id, 2.days.ago, 2], ['professional', rewrite_group_id, latest_rewrite_event_at, 4],
      ['friendly', SecureRandom.uuid, 3.days.ago, 1], ['faq_generation', faq_group_id, latest_faq_event_at, 1]
    ].each do |feature, group_id, created_at, units|
      AiUsageEvent.create!(account: account, bucket: Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch(feature).to_s,
                           feature: feature, model: 'private-model', provider: 'private-provider',
                           usage_group_id: group_id, created_at: created_at, status: 'ok', cost_usd: 12, units: units,
                           input_tokens: 100)
    end
    AiUsageEvent.create!(account: account, bucket: 'internal', feature: 'summary', model: 'm', provider: 'p',
                         usage_group_id: SecureRandom.uuid, created_at: 1.hour.ago, status: 'error')

    result = described_class.new(account: account, period: period).build

    expect(result[:buckets]['internal']).to contain_exactly(
      include(feature: :rewrite_message, name: 'Rewrite messages', operations: 2, units: 5,
              last_used_at: be_within(1.second).of(latest_rewrite_event_at))
    )
    expect(result[:buckets]['captain_responses']).to contain_exactly(
      include(feature: :document_faq_generation, operations: 1, units: 1,
              last_used_at: be_within(1.second).of(latest_faq_event_at))
    )
  end

  it 'assigns every configured feature to exactly one friendly group' do
    expect(described_class::FEATURE_GROUPS.keys).to match_array(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.keys)
  end

  it 'has translated names for every group in English and Spanish' do
    feature_groups = described_class::FEATURE_GROUPS.values.uniq

    %i[en es].each do |locale|
      feature_groups.each do |feature_group|
        expect(I18n.t("captain.usage_breakdown.features.#{feature_group}", locale: locale))
          .not_to match(/translation missing/)
      end
    end
  end

  it 'returns an empty bucket list when no billing period exists' do
    expect(described_class.new(account: account, period: nil).build).to include(
      period_start: nil, period_end: nil, buckets: include('internal' => [])
    )
  end
end
