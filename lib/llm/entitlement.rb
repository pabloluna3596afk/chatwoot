class Llm::Entitlement
  # These utilities use the response allowance but are exposed by the Captain Tasks feature.
  TASK_FEATURE_GATES = %w[article_translation language_detection message_translation].freeze
  FEATURE_GATES = {
    internal: 'captain_tasks',
    copilot: 'captain_integration',
    captain_responses: 'captain_integration'
  }.freeze

  def initialize(account:, feature:)
    @account = account
    @feature = feature.to_s
    @bucket = Llm::UsageContext.bucket_for(@feature)
    @required_gate = TASK_FEATURE_GATES.include?(@feature) ? 'captain_tasks' : FEATURE_GATES.fetch(@bucket)
  end

  def call
    captain_limits = @account.usage_limits[:captain]
    remaining = remaining_allowance(captain_limits)
    reason = denial_reason(remaining)

    {
      allowed: reason.nil?, reason: reason, bucket: @bucket,
      remaining: remaining, required_gate: @required_gate, required_plan: @account.plan&.slug,
      error_code: error_code(reason),
      error: error_message(reason)
    }
  end

  def error_message(reason = call[:reason])
    return if reason.nil?
    return 'Captain integration is not enabled for this account' if reason == :feature_disabled

    # Accounts without a billing period (self-hosted, legacy) have no reset date to show.
    period_end = @account.current_usage_period&.period_end
    return I18n.t('captain.copilot_limit_no_date') if period_end.nil?

    I18n.t('captain.copilot_limit', reset_date: period_end.to_date)
  end

  private

  def remaining_allowance(captain_limits)
    return captain_limits.dig(:responses, :current_available) if @bucket == :copilot && captain_limits.dig(:copilot, :total_count).nil?

    captain_limits.dig(usage_limit_key, :current_available)
  end

  def denial_reason(remaining)
    return :feature_disabled unless @account.feature_enabled?(@required_gate)
    return :usage_limit_reached if remaining.to_i.zero?

    nil
  end

  def error_code(reason)
    return 403 if reason == :feature_disabled
    return 429 if reason

    nil
  end

  def usage_limit_key
    return :responses if @bucket == :captain_responses

    @bucket
  end
end
