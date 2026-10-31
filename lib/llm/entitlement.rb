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
    remaining = captain_limits.dig(usage_limit_key, :current_available)
    remaining = captain_limits.dig(:responses, :current_available) if @bucket == :copilot && captain_limits.dig(:copilot, :total_count).nil?
    reason = if !@account.feature_enabled?(@required_gate)
               :feature_disabled
             elsif remaining.to_i.zero?
               :usage_limit_reached
             end

    {
      allowed: reason.nil?, reason: reason, bucket: @bucket,
      remaining: remaining, required_gate: @required_gate, required_plan: @account.plan&.slug
    }
  end

  private

  def usage_limit_key
    return :responses if @bucket == :captain_responses

    @bucket
  end
end
