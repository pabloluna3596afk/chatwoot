class AutomationRules::PurgeRunsJob < ApplicationJob
  queue_as :purgable

  def perform
    AutomationRuleRun.where(created_at: ...AutomationRuleRun::RETENTION_WINDOW.ago).in_batches(of: 1000).delete_all
  end
end
