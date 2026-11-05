# Durable receipt tying one preflight quota reservation to its eventual
# success or release. Closed receipts keep their units until the existing
# retention cleanup so usage events can be reconciled; released calls are
# refunded while successful calls remain consumed. Provider events are separate.
class AiUsageReservation < ApplicationRecord
  belongs_to :account_plan_usage

  validates :reservation_id, presence: true, uniqueness: true
  validates :bucket, inclusion: { in: %w[internal copilot captain_responses] }
  validates :units, numericality: { only_integer: true, greater_than: 0 }
end
