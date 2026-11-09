require 'rails_helper'

RSpec.describe Account do
  let(:account) { create(:account) }
  let(:reference) { SecureRandom.uuid }
  let(:balance) do
    account.grant_extra_balance!(bucket: :internal, units: 100, source: :courtesy, expires_at: 90.days.from_now)
  end

  before { put_account_on_plan(account, captain_internal_calls: 0) }

  it 'consumes extras after exhausting the plan and records their funding on provider events' do
    balance
    expect(account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reference, units: 3)).to be(true)
    Llm::UsageContext.with(account: account, feature: 'summary', reservation_id: reference, units: 3) do
      Llm::UsageContext.record_operation(model: 'test-model', provider: 'test', status: 'ok', response: {})
    end
    expect(AiUsageEvent.last.extra_units).to eq(3)
    expect(account.finish_captain_ai_usage!(bucket: :internal, reservation_id: reference)).to be(true)
    expect(balance.reload.units_remaining).to eq(97)
    expect(account.current_usage_period.internal_calls_consumed).to eq(0)
    expect(AiUsageReservation.find_by(reservation_id: reference)).to be_nil
  end

  it 'mixes plan units and extra balances in expiration order and refunds each source once' do
    account.plan.update!(captain_internal_calls: 2)
    later = balance
    earlier = account.grant_extra_balance!(bucket: :internal, units: 3, source: :manual, expires_at: 1.day.from_now)
    expect(account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reference, units: 7)).to be(true)
    expect([account.current_usage_period.internal_calls_consumed, earlier.reload.units_remaining, later.reload.units_remaining]).to eq([2, 0, 98])
    expect(account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reference, units: 7)).to be(true)
    expect(account.release_captain_ai_usage!(bucket: :internal, reservation_id: reference)).to be(true)
    expect(account.release_captain_ai_usage!(bucket: :internal, reservation_id: reference)).to be(false)
    expect(account.current_usage_period.internal_calls_consumed).to eq(0)
    expect([earlier.reload.units_remaining, later.reload.units_remaining]).to eq([3, 100])
  end

  it 'leaves all counters untouched when the combined balance is insufficient' do
    account.plan.update!(captain_internal_calls: 2)
    balance
    expect(account.reserve_captain_ai_usage!(bucket: :internal, units: 103)).to be(false)
    expect(balance.reload.units_remaining).to eq(100)
    expect(account.current_usage_period.internal_calls_consumed).to eq(0)
    expect(AiUsageReservation.count).to eq(0)
  end

  it 'allows the exact remaining balance and rejects the next reservation' do
    balance
    expect(account.reserve_captain_ai_usage!(bucket: :internal, units: 100)).to be(true)
    expect(account.reserve_captain_ai_usage!(bucket: :internal)).to be(false)
    expect(balance.reload.units_remaining).to eq(0)
  end

  it 'excludes expired balances and does not resurrect units when released after expiry' do
    travel_to(1.second.from_now.change(usec: 0)) do
      balance.update!(expires_at: 1.minute.from_now)
      account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reference, units: 10)
      travel 1.minute
      expect(account.extra_available(:internal)).to eq(0)
      expect(account.reserve_captain_ai_usage!(bucket: :internal)).to be(false)
      expect(account.release_captain_ai_usage!(bucket: :internal, reservation_id: reference)).to be(true)
      expect(balance.reload.units_remaining).to eq(90)
    end
  end

  it 'keeps a pending extra receipt refundable across a billing period change' do
    balance
    account.reserve_captain_ai_usage!(bucket: :internal, reservation_id: reference)
    account.update!(plan_started_at: 1.hour.ago)
    account.reserve_captain_ai_usage!(bucket: :internal)
    expect(account.release_captain_ai_usage!(bucket: :internal, reservation_id: reference)).to be(true)
    expect(balance.reload.units_remaining).to eq(99)
  end

  it 'includes extras in usage limits and knowledge estimates' do
    balance
    expect(account.usage_limits.dig(:captain, :internal)).to include(extra_available: 100, current_available: 100, total_count: 0)
    estimate = Captain::Documents::UsageEstimate.for_units(account: account, units: 2)
    expect(estimate).to include(sufficient: true)
  end

  %i[captain_responses copilot].each do |bucket|
    it "uses only the #{bucket} extra bag after its plan allowance" do
      account.plan.update!(monthly_messages: 0, captain_copilot_responses: 0)
      credit = account.grant_extra_balance!(bucket: bucket, units: 1, source: :courtesy, expires_at: 90.days.from_now)
      expect(account.reserve_captain_ai_usage!(bucket: bucket)).to be(true)
      expect(account.reserve_captain_ai_usage!(bucket: bucket)).to be(false)
      expect(credit.reload.units_remaining).to eq(0)
    end
  end

  it 'uses Copilot extras when Copilot shares the plan response allowance' do
    account.plan.update!(monthly_messages: 0, captain_copilot_responses: nil)
    account.grant_extra_balance!(bucket: :copilot, units: 2, source: :courtesy, expires_at: 90.days.from_now)
    expect(account.copilot_responses_available?).to be(true)
    expect(account.reserve_captain_ai_usage!(bucket: :copilot)).to be(true)
    expect(account.current_usage_period.copilot_responses_consumed).to eq(0)
  end

  it 'preserves balances for accounts with unlimited internal actions' do
    account.plan.update!(limits: { 'captain_internal_calls' => nil })
    balance
    expect(account.reserve_captain_ai_usage!(bucket: :internal, units: 101)).to be(true)
    expect(balance.reload.units_remaining).to eq(100)
  end

  it 'preserves unmetered behavior for accounts without a plan' do
    balance
    account.update!(plan: nil, plan_started_at: nil)
    expect(account.reserve_captain_ai_usage!(bucket: :internal, units: 101)).to be(true)
    expect(balance.reload.units_remaining).to eq(100)
  end
end
