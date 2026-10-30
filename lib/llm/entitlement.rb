class Llm::Entitlement
  FEATURE_GATES = {
    internal: 'captain_tasks',
    copilot: 'captain_integration',
    captain_responses: 'captain_integration'
  }.freeze

  def initialize(account:, feature:)
    @account = account
    @feature = feature.to_s
    @bucket = Llm::UsageContext.bucket_for(@feature)
    @required_gate = FEATURE_GATES.fetch(@bucket)
  end

  def call
    remaining = @account.usage_limits.dig(:captain, usage_limit_key, :current_available)
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
    @bucket == :captain_responses ? :responses : @bucket
  end
end
