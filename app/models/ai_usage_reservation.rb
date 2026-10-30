# Durable receipt tying one preflight quota reservation to its eventual
# success or release. Failed receipts remain as per-period idempotency markers;
# successful receipts are consumed. Provider usage events remain separate: a
# failed provider call can incur cost while its quota reservation is refunded.
class AiUsageReservation < ApplicationRecord
  belongs_to :account_plan_usage

  validates :reservation_id, presence: true, uniqueness: true
  validates :bucket, inclusion: { in: %w[internal copilot] }
end
