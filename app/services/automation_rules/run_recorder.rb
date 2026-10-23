class AutomationRules::RunRecorder
  DAILY_LIMIT = 1000

  # Never raises: a failed record must not break the automation it describes.
  def self.record(rule:, outcome:, reason: nil, conversation: nil, contact: nil, event_name: nil, details: {}) # rubocop:disable Metrics/ParameterLists
    # A savepoint keeps a failed INSERT from poisoning a caller's transaction. There is no row lock on purpose:
    # the daily limit is a volume guard, so a small overshoot under concurrency is fine and rules never wait on each other.
    AutomationRuleRun.transaction(requires_new: true) do
      runs = AutomationRuleRun.where(automation_rule_id: rule.id, created_at: Time.current.all_day)
      next increment_suppressed_count(runs) if outcome == 'executed' && runs.count >= DAILY_LIMIT

      create_run(rule, outcome, reason, conversation, contact, event_name, details)
    end
  rescue StandardError => e
    Rails.logger.error("[AutomationRules::RunRecorder] record failed: #{e.class.name}")
    nil
  end

  def self.create_run(rule, outcome, reason, conversation, contact, event_name, details) # rubocop:disable Metrics/ParameterLists
    AutomationRuleRun.create!(account_id: rule.account_id, automation_rule_id: rule.id,
                              conversation_id: conversation&.id, contact_id: contact&.id || conversation&.contact_id,
                              event_name: event_name || rule.event_name, outcome: outcome, reason: reason,
                              details: details, created_at: Time.current)
  end
  private_class_method :create_run

  def self.increment_suppressed_count(runs)
    last_run = runs.order(created_at: :desc, id: :desc).first!
    details = last_run.details
    last_run.update!(details: details.merge('suppressed_executed_count' => details.fetch('suppressed_executed_count', 0) + 1))
  end
  private_class_method :increment_suppressed_count
end
