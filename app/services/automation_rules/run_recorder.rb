class AutomationRules::RunRecorder
  DAILY_LIMIT = 1000

  # rubocop:disable Metrics/ParameterLists
  def self.record(rule:, outcome:, reason: nil, conversation: nil, contact: nil, event_name: nil, details: {})
    # A savepoint keeps a failed INSERT from poisoning a caller's transaction.
    AutomationRuleRun.transaction(requires_new: true) do
      # Serialize the count and insert, including when a rule has no runs yet.
      AutomationRule.where(id: rule.id).lock.first!
      recorded_at = Time.current
      runs = AutomationRuleRun.where(automation_rule_id: rule.id, created_at: recorded_at.all_day)
      if outcome == 'executed' && runs.count >= DAILY_LIMIT
        increment_suppressed_count(runs)
      else
        AutomationRuleRun.create!(account_id: rule.account_id, automation_rule_id: rule.id,
                                  conversation_id: conversation&.id, contact_id: contact&.id || conversation&.contact_id,
                                  event_name: event_name || rule.event_name, outcome: outcome, reason: reason,
                                  details: details, created_at: recorded_at)
      end
    end
  rescue StandardError => e
    Rails.logger.error("[AutomationRules::RunRecorder] record failed: #{e.class.name}")
    nil
  end

  # rubocop:enable Metrics/ParameterLists

  def self.increment_suppressed_count(runs)
    last_run = runs.order(created_at: :desc, id: :desc).first!
    details = last_run.details
    last_run.update!(details: details.merge('suppressed_executed_count' => details.fetch('suppressed_executed_count', 0) + 1))
  end
  private_class_method :increment_suppressed_count
end
