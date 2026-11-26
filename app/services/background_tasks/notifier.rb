class BackgroundTasks::Notifier
  STATUSES = %w[running success error].freeze
  PHASES = %w[running waiting].freeze

  # Register any module's task through this entry point:
  # publish(account: account, id: 'import:42', kind: 'import', title: 'Contacts', status: 'running')
  # Publish again with the same id and status: 'success' or 'error' to finish it.
  def self.publish(account:, id:, kind:, title:, status:, phase: 'running',
                   detail: nil, link: nil) # rubocop:disable Metrics/ParameterLists -- Shared task contract
    raise ArgumentError, 'Invalid background task status' unless STATUSES.include?(status)
    raise ArgumentError, 'Invalid background task phase' unless PHASES.include?(phase)

    now = Time.current
    task = { id: id, kind: kind, title: title, status: status, phase: status == 'running' ? phase : nil,
             version: now.to_f, updated_at: now.iso8601, detail: detail, link: link }
    Rails.configuration.dispatcher.dispatch(Events::Types::BACKGROUND_TASK_UPDATED, Time.current, account: account, task: task)
  end
end
