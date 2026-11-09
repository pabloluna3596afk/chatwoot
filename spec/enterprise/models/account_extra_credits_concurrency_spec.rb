require 'rails_helper'

RSpec.describe Account, 'concurrent extra credit reservations' do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }

  before do
    put_account_on_plan(account, captain_internal_calls: 0)
    account.grant_extra_balance!(bucket: :internal, units: 1, source: :courtesy, expires_at: 1.day.from_now)
  end

  after do
    AccountExtraBalance.where(account: account).delete_all
    account.account_plan_usages.destroy_all
    plan = account.plan
    account.destroy!
    plan.destroy!
  end

  it 'admits only one of two concurrent reservations for the same last extra unit' do
    ready = Queue.new
    start = Queue.new
    attempts = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Account.find(account.id).reserve_captain_ai_usage!(bucket: :internal)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(attempts.map(&:value).count(true)).to eq(1)
    expect(account.extra_available(:internal)).to eq(0)
    expect(account.current_usage_period.internal_calls_consumed).to eq(0)
  ensure
    attempts&.each { |attempt| attempt.kill if attempt.alive? }
  end
end
