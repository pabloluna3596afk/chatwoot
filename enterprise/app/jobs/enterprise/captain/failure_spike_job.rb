module Enterprise::Captain::FailureSpikeJob
  DEFAULT_THRESHOLD = 10
  THRESHOLD_RANGE = (1..1000)

  def perform
    super

    now = Time.current
    threshold = failure_threshold
    count = ConversationOutcome.where(handoff_reason_category: 'tool_failure', handoff_at: (now - 60.minutes)..now).count
    return if count < threshold
    return unless Redis::Alfred.set("captain:failure_spike:#{now.utc.strftime('%Y%m%d%H')}", '1', nx: true, ex: 2.hours.to_i)

    ChatwootExceptionTracker.new(Captain::FailureSpikeError.new("#{count} Captain failure handoffs in the last hour")).capture_exception
    Rails.logger.warn("[CAPTAIN][Alert] event=failure_spike count=#{count} threshold=#{threshold}")
  end

  private

  def failure_threshold
    value = Integer(InstallationConfig.find_by(name: 'CAPTAIN_FAILURE_ALERT_THRESHOLD')&.value.to_s, exception: false)
    (value || DEFAULT_THRESHOLD).clamp(THRESHOLD_RANGE.min, THRESHOLD_RANGE.max)
  end
end
