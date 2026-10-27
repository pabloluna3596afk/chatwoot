require 'rails_helper'

RSpec.describe Captain::Playground::Usage, :real_redis do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:usage) { described_class.new(account: account) }
  let(:success) { { response: 'Hello' }.with_indifferent_access }
  let(:daily_key) { "captain:playground:daily:#{account.id}:#{Time.current.in_time_zone(account.reporting_timezone).to_date}" }
  let(:rate_key) { "captain:playground:rate:#{account.id}" }

  after do
    Redis::Alfred.delete(daily_key)
    Redis::Alfred.delete(rate_key)
  end

  it 'charges every free-plan test to the shared pool even with a configured allowance' do
    put_account_on_plan(account, captain_daily_tests: 10)
    expect { usage.perform { success } }.to change { captain_responses_used(account) }.by(1)
    expect(usage.test_usage).to include(plan_kind: 'free', daily_total: 0, daily_used: 0, uses_plan_pool: true, plan_remaining: 99)
  end

  it 'treats default trial plans as free even with a nonzero price' do
    put_account_on_plan(account, is_default_trial: true, price_monthly: 10, captain_daily_tests: 10)
    expect { usage.perform { success } }.to change { captain_responses_used(account) }.by(1)
    expect(usage.test_usage[:daily_remaining]).to eq(0)
  end

  it 'treats an explicitly empty daily test limit as unlimited, including on a free plan' do
    plan = put_account_on_plan(account, captain_daily_tests: 10)
    plan.update!(limits: { captain_daily_tests: nil })
    account.reload

    expect(usage.test_usage).to include(daily_total: nil, daily_remaining: ChatwootApp.max_limit, uses_plan_pool: false)
  end

  it 'uses the paid daily allowance first, then the plan without a hard daily ceiling' do
    put_account_on_plan(account, price_monthly: 79, captain_daily_tests: 1)
    expect(usage.perform { success }[:test_usage]).to include(daily_used: 1, daily_remaining: 0, plan_remaining: 100)
    expect(usage.perform { success }[:test_usage]).to include(daily_used: 1, plan_remaining: 99, uses_plan_pool: true)
    Redis::Alfred.setex(daily_key, 100, 60)
    expect(usage.perform { success }[:test_usage][:plan_remaining]).to eq(98)
  end

  it 'does not debit either daily allowance or plan on model errors and missing keys' do
    put_account_on_plan(account, price_monthly: 79, captain_daily_tests: 10)
    expect { usage.perform { raise 'Missing API key' } }.to raise_error('Missing API key')
    expect(usage.perform { { error: true }.with_indifferent_access }[:test_usage]).to include(daily_used: 0, plan_remaining: 100)
    Redis::Alfred.setex(daily_key, 10, 60)
    expect(usage.perform { { error: true }.with_indifferent_access }[:test_usage][:plan_remaining]).to eq(100)
  end

  it 'blocks before the model at exactly zero available plan responses' do
    put_account_on_plan(account, used: 100)
    expect { usage.perform { raise 'Must not generate' } }.to raise_error(described_class::LimitExceeded) { |e|
      expect(e.code).to eq('responses_limit_reached')
      expect(e.status).to eq(:unprocessable_entity)
    }
  end

  it 'allows the daily allowance even when the paid plan pool is exhausted' do
    put_account_on_plan(account, used: 100, price_monthly: 79, captain_daily_tests: 10)
    expect(usage.perform { success }[:test_usage]).to include(daily_remaining: 9, plan_remaining: 0)
  end

  it 'retains unlimited fallback and skips all accounting without a plan' do
    account.update!(plan: nil)
    expect(usage.perform { success }[:test_usage]).to be_nil
    expect(account.usage_limits[:captain][:responses][:current_available]).to eq(ChatwootApp.max_limit)
    expect(account.account_plan_usages.open).to be_empty
    expect(Redis::Alfred.get(daily_key)).to be_nil
  end

  it 'exempts a confirmed own key from both pools even with a zero-message Developer plan' do
    put_account_on_plan(account, price_monthly: 49, monthly_messages: 0, captain_daily_tests: 10)
    allow(account).to receive(:own_ai_key_configured?).and_return(true)
    expect(usage.perform { success }[:test_usage]).to be_nil
    expect(captain_responses_used(account)).to eq(0)
    expect(Redis::Alfred.get(daily_key)).to be_nil
  end

  it 'treats Developer without an own key as paid and blocks only after its allowance' do
    put_account_on_plan(account, price_monthly: 49, monthly_messages: 0, captain_daily_tests: 1)
    expect(usage.perform { success }[:test_usage]).to include(daily_used: 1, plan_remaining: 0)
    expect { usage.perform { raise 'Must not generate' } }.to raise_error(described_class::LimitExceeded)
  end

  it 'shares the rolling-minute limit across all users and assistants of the account' do
    travel_to Time.zone.parse('2026-10-17 12:00:00') do
      6.times { described_class.new(account: Account.find(account.id)).perform { success } }
      expect { usage.perform { raise 'Must not generate' } }.to raise_error(described_class::LimitExceeded) { |e|
        expect(e.code).to eq('playground_rate_limit')
        expect(e.retry_after).to eq(60)
      }
      travel 60.seconds
      expect(usage.perform { success }[:response]).to eq('Hello')
    end
  end

  it 'shares allowance between separately loaded tabs without spending the final daily credit twice' do
    put_account_on_plan(account, price_monthly: 79, captain_daily_tests: 1)
    other_tab = described_class.new(account: Account.find(account.id))
    expect(usage.perform { success }[:test_usage][:daily_remaining]).to eq(0)
    expect(other_tab.perform { success }[:test_usage][:plan_remaining]).to eq(99)
  end

  it 'applies a changed plan allowance to tests already used today' do
    plan = put_account_on_plan(account, price_monthly: 79, captain_daily_tests: 1)
    usage.perform { success }
    plan.update!(captain_daily_tests: 20)
    expect(described_class.new(account: account.reload).test_usage).to include(daily_used: 1, daily_remaining: 19)
    account.update!(plan: Plan.create!(name: 'Trial', slug: 'trial'))
    expect(described_class.new(account: account.reload).test_usage).to include(plan_kind: 'free', daily_remaining: 0)
  end

  it 'expires the daily counter at account midnight and starts a new allowance' do
    put_account_on_plan(account, price_monthly: 79, captain_daily_tests: 10)
    midnight = Time.current.in_time_zone(account.reporting_timezone).tomorrow.beginning_of_day
    travel_to midnight - 1.minute do
      old_key = daily_key
      usage.perform { success }
      expected_ttl = midnight.to_i - Process.clock_gettime(Process::CLOCK_REALTIME).to_i
      expect(Redis::Alfred.ttl(old_key)).to be_within(5).of(expected_ttl)
      travel 61.seconds
      next_day = described_class.new(account: account)
      expect(next_day.perform { success }[:test_usage][:daily_remaining]).to eq(9)
    end
  end
end
