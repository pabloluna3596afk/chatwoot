class AutomationRules::TriggerPendingExecutionsJob < ApplicationJob
  queue_as :scheduled_jobs

  DEFAULT_SWEEP_LIMIT = 1000

  def perform
    started_at = Time.current
    purged = AutomationRulePendingExecution.purge_terminal!

    rows = sweep_rows
    rows.each { |row| AutomationRules::ProcessPendingExecutionJob.perform_later(row) }

    log_summary(enqueued: rows.size, capped: rows.size >= sweep_limit, purged: purged,
                abandoned: AutomationRulePendingExecution.abandoned.count, started_at: started_at)
  end

  private

  def sweep_rows
    # Keep the due-time cap unchanged; order only the selected rows for enqueueing.
    selected = AutomationRulePendingExecution.sweepable.for_enabled_accounts.order(:due_at).limit(sweep_limit)
    AutomationRulePendingExecution.where(id: selected.select(:id))
                                  .left_joins(:automation_rule).merge(AutomationRule.in_execution_order)
                                  .order(:due_at, :id).to_a
  end

  def sweep_limit
    (InstallationConfig.find_by(name: 'AUTOMATION_PENDING_EXECUTIONS_SWEEP_LIMIT')&.value || DEFAULT_SWEEP_LIMIT).to_i
  end

  def log_summary(enqueued:, capped:, purged:, abandoned:, started_at:)
    summary = { event: 'completed', enqueued: enqueued, capped: capped, purged: purged, abandoned: abandoned,
                duration_ms: ((Time.current - started_at) * 1000).round }
    Rails.logger.info("[AutomationRules::TriggerPendingExecutionsJob] #{summary.to_json}")
  end
end
