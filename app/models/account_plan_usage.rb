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
  has_many :ai_usage_reservations, dependent: :delete_all

  scope :open, -> { where(closed_at: nil) }

  # Atomic — safe under concurrent inbound messages hitting the same period.
  # rubocop:disable Rails/SkipsModelValidations
  def increment_responses!(source: :customer, shared_response_pool: false, warning_limit: limit_responses)
    increment_usage_counters!(source)
    if shared_response_pool
      check_usage_limit_warning(:responses, shared_response_pool_consumed, warning_limit)
    elsif source == :copilot
      check_usage_limit_warning(:copilot, copilot_responses_consumed, warning_limit)
    else
      check_usage_limit_warning(:responses, responses_consumed, warning_limit)
    end
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

  def check_usage_limit_warning(bucket, consumed, limit)
    return unless limit&.positive?

    [80, 100].each do |threshold|
      next unless (consumed.to_f / limit) * 100 >= threshold

      warning_column = "warned_at_#{bucket}_#{threshold}_percent"
      claimed = self.class.where(id: id).where(warning_column => false).update_all(warning_column => true)
      Captain::UsageLimitWarningJob.perform_later(self, bucket, threshold, consumed, limit) if claimed.positive?
    end
  end

  def check_ai_usage_warning(bucket, shared_response_pool, column, limit)
    consumed = shared_response_pool ? shared_response_pool_consumed : self[column]
    check_usage_limit_warning(shared_response_pool ? :responses : bucket, consumed, limit)
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
  def reserve_ai_call!(bucket:, limit:, shared_response_pool: false)
    column = case bucket
             when :internal then :internal_calls_consumed
             when :copilot then :copilot_responses_consumed
             else raise ArgumentError, "Unsupported AI usage bucket: #{bucket}"
             end
    updates = ["#{column} = #{column} + 1"]
    self.class.where(id: id).update_all(updates.join(', '))
    self[column] = self.class.where(id: id).pick(column)
    self.responses_consumed = self.class.where(id: id).pick(:responses_consumed)
    check_ai_usage_warning(bucket, shared_response_pool, column, limit)
  end

  # The caller holds the account lock and a matching unreleased reservation
  # receipt, so a retry cannot refund a different in-flight request.
  def release_ai_call!(bucket:)
    column = case bucket
             when :internal then :internal_calls_consumed
             when :copilot then :copilot_responses_consumed
             else raise ArgumentError, "Unsupported AI usage bucket: #{bucket}"
             end
    self.class.where(id: id).where("#{column} > 0").update_all("#{column} = #{column} - 1")
    self[column] = self.class.where(id: id).pick(column)
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
