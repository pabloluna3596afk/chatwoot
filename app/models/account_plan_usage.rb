# == Schema Information
#
# Table name: account_plan_usages
#
#  id                 :bigint           not null, primary key
#  closed_at          :datetime
#  copilot_responses_consumed :integer  default(0), not null
#  documents_consumed :integer          default(0), not null
#  internal_calls_consumed :integer     default(0), not null
#  limit_documents    :integer
#  limit_responses    :integer
#  limit_copilot_responses :integer
#  limit_internal_calls :integer
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
  def increment_responses!(source: :customer, shared_response_pool: false)
    increment_usage_counters!(source)
    check_usage_limit_warnings(shared_response_pool ? shared_response_pool_consumed : responses_consumed)
  end

  private

  def increment_usage_counters!(source)
    updates = []
    updates << 'responses_consumed = responses_consumed + 1' if source != :copilot
    updates << 'copilot_responses_consumed = copilot_responses_consumed + 1' if source == :copilot
    self.class.where(id: id).update_all(updates.join(', '))
    self.responses_consumed = self.class.where(id: id).pick(:responses_consumed)
    self.copilot_responses_consumed = self.class.where(id: id).pick(:copilot_responses_consumed) if source == :copilot
  end

  def check_usage_limit_warnings(consumed = responses_consumed)
    # Check for usage limit warnings (80% and 100%)
    # Only warn accounts with a real plan (limit_responses.present? accounts without a plan have no meaningful percentage)
    return unless limit_responses.present? && limit_responses.positive?

    usage_percentage = (consumed.to_f / limit_responses) * 100

    warn_at_threshold(usage_percentage, 80, :warned_at_80_percent)
    warn_at_threshold(usage_percentage, 100, :warned_at_100_percent)
  end

  def warn_at_threshold(usage_percentage, threshold, warning_column)
    return unless usage_percentage >= threshold && !public_send(warning_column)

    Captain::UsageLimitWarningJob.perform_later(self, threshold)
    self.class.where(id: id).update_all(warning_column => true)
  end

  public

  def shared_response_pool_consumed
    responses_consumed + copilot_responses_consumed
  end

  # Returns the Captain response pool usage, including Copilot when it shares that pool.
  def customer_responses_consumed
    responses_consumed
  end

  # Charge AI calls before contacting the provider so concurrent workers
  # cannot consume the same remaining credit.
  def reserve_ai_call!(bucket:, shared_response_pool: false)
    column = case bucket
             when :internal then :internal_calls_consumed
             when :copilot then :copilot_responses_consumed
             else raise ArgumentError, "Unsupported AI usage bucket: #{bucket}"
             end
    updates = ["#{column} = #{column} + 1"]
    self.class.where(id: id).update_all(updates.join(', '))
    public_send("#{column}=", self.class.where(id: id).pick(column))
    self.responses_consumed = self.class.where(id: id).pick(:responses_consumed)
    check_usage_limit_warnings(shared_response_pool_consumed) if shared_response_pool
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
