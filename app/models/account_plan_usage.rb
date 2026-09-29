# == Schema Information
#
# Table name: account_plan_usages
#
#  id                 :bigint           not null, primary key
#  closed_at          :datetime
#  documents_consumed :integer          default(0), not null
#  limit_documents    :integer
#  limit_responses    :integer
#  period_end         :datetime         not null
#  period_start       :datetime         not null
#  responses_consumed :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  plan_id            :bigint
#
# Indexes
#
#  index_account_plan_usages_on_account_and_period_start  (account_id,period_start) UNIQUE
#  index_account_plan_usages_on_account_id_open            (account_id) WHERE (closed_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (plan_id => plans.id)
#

# One row per account per billing period (anchored to Account#plan_started_at,
# monthly). This is the cheap materialized counter read on the hot path
# (every inbound message, via Enterprise::Inbox#more_responses?) — never
# derive it with a SUM over `Captain::AgentSession`, which stays the
# detailed, per-run audit ledger instead.
#
# Rows are immutable snapshots once `closed_at` is set: `plan_id`,
# `limit_responses` and `limit_documents` are captured at creation time so a
# later edit to a Plan's numbers (or reassigning the account to a different
# plan) never rewrites history.
class AccountPlanUsage < ApplicationRecord
  belongs_to :account
  belongs_to :plan, optional: true

  scope :open, -> { where(closed_at: nil) }

  # Atomic — safe under concurrent inbound messages hitting the same period.
  # rubocop:disable Rails/SkipsModelValidations
  def increment_responses!(source: :customer)
    if source == :copilot
      # When source is copilot, increment only copilot responses
      self.class.where(id: id).update_all(
        'copilot_responses_consumed = copilot_responses_consumed + 1'
      )
      self.copilot_responses_consumed = self.class.where(id: id).pick(:copilot_responses_consumed)
      self.responses_consumed = self.class.where(id: id).pick(:responses_consumed)
    else
      # Default behavior for customer responses
      self.class.where(id: id).update_all('responses_consumed = responses_consumed + 1')
      self.responses_consumed = self.class.where(id: id).pick(:responses_consumed)
    end

    # Check for usage limit warnings (80% and 100%)
    # Only warn accounts with a real plan (limit_responses.present? accounts without a plan have no meaningful percentage)
    if limit_responses.present? && limit_responses > 0
      usage_percentage = (responses_consumed.to_f / limit_responses) * 100

      # Check 80% threshold
      if usage_percentage >= 80 && !warned_at_80_percent
        Captain::UsageLimitWarningJob.perform_later(self, 80)
        self.class.where(id: id).update_all(warned_at_80_percent: true)
      end

      # Check 100% threshold
      if usage_percentage >= 100 && !warned_at_100_percent
        Captain::UsageLimitWarningJob.perform_later(self, 100)
        self.class.where(id: id).update_all(warned_at_100_percent: true)
      end
    end
  end

  # Returns the count of customer-facing Captain replies (total responses minus copilot usage)
  def customer_responses_consumed
    responses_consumed
  end

  def set_documents_consumed!(count)
    self.class.where(id: id).update_all(documents_consumed: count)
    self.documents_consumed = count
  end

  def set_storage_consumed!(bytes)
    self.class.where(id: id).update_all(storage_consumed: bytes)
    self.storage_consumed = bytes
  end
  # rubocop:enable Rails/SkipsModelValidations
end
