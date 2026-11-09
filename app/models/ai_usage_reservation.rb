# Durable receipt tying one preflight quota reservation to its eventual
# success or release. Failed receipts remain as per-period idempotency markers;
# successful receipts are consumed. Provider usage events remain separate: a
# failed provider call can incur cost while its quota reservation is refunded.
class AiUsageReservation < ApplicationRecord
  belongs_to :account_plan_usage

  validates :reservation_id, presence: true, uniqueness: true
  validates :bucket, inclusion: { in: %w[internal copilot captain_responses] }
  validates :units, numericality: { only_integer: true, greater_than: 0 }
  def refund!
    account_plan_usage.release_ai_call!(bucket: bucket.to_sym, units: plan_units || units)
    extra_allocations.each do |balance_id, refunded_units|
      balance = account_plan_usage.account.account_extra_balances.lock.find(balance_id)
      next unless balance.expires_at > Time.current

      balance.update!(units_remaining: balance.units_remaining + refunded_units)
    end
  end
end
