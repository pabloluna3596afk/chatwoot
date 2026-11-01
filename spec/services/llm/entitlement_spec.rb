require 'rails_helper'

RSpec.describe Llm::Entitlement do
  let(:account) { create(:account) }

  it 'returns the mapped bucket, gate, and available allowance when the feature is enabled' do
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 4 } })

    expect(described_class.new(account: account, feature: 'summarize').call).to include(
      allowed: true, reason: nil, bucket: :internal, remaining: 4,
      required_gate: 'captain_tasks'
    )
  end

  it 'denies a disabled feature before considering its remaining allowance' do
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)
    allow(account).to receive(:usage_limits).and_return(captain: { internal: { current_available: 4 } })

    expect(described_class.new(account: account, feature: 'summarize').call).to include(
      allowed: false, reason: :feature_disabled, bucket: :internal
    )
  end

  it 'denies an exhausted bucket' do
    put_account_on_plan(account)
    allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(true)
    allow(account).to receive(:usage_limits).and_return(captain: { copilot: { current_available: 0 } })

    expect(described_class.new(account: account, feature: 'copilot').call).to include(
      allowed: false, reason: :usage_limit_reached, bucket: :copilot
    )
  end

  it 'uses the shared response allowance when no Copilot-specific limit is configured' do
    put_account_on_plan(account)
    allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(true)
    allow(account).to receive(:usage_limits).and_return(
      captain: {
        copilot: { total_count: nil, current_available: ChatwootApp.max_limit },
        responses: { current_available: 0 }
      }
    )

    expect(described_class.new(account: account, feature: 'copilot').call).to include(
      allowed: false, reason: :usage_limit_reached, bucket: :copilot, remaining: 0
    )
  end

  it 'uses the Captain Tasks gate while keeping translation usage in the response bucket' do
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: 4 } })

    expect(described_class.new(account: account, feature: 'message_translation').call).to include(
      allowed: true, reason: nil, bucket: :captain_responses, remaining: 4, required_gate: 'captain_tasks'
    )
  end

  it 'explains an exhausted allowance without a billing period instead of raising' do
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: 0 } })
    allow(account).to receive(:current_usage_period).and_return(nil)

    expect(described_class.new(account: account, feature: 'summarize').call).to include(
      allowed: false, reason: :usage_limit_reached, error_code: 429, error: I18n.t('captain.copilot_limit_no_date')
    )
  end
end
