class BackgroundTasks::Notifier
  STATUSES = %w[running success error].freeze

  # Register any module's task through this entry point:
  # publish(account: account, id: 'import:42', kind: 'import', title: 'Contacts', status: 'running')
  # Publish again with the same id and status: 'success' or 'error' to finish it.
  def self.publish(account:, id:, kind:, title:, status:, detail: nil, link: nil) # rubocop:disable Metrics/ParameterLists -- Shared task contract
    raise ArgumentError, 'Invalid background task status' unless STATUSES.include?(status)

    task = { id: id, kind: kind, title: title, status: status, detail: detail, link: link }
    Rails.configuration.dispatcher.dispatch(Events::Types::BACKGROUND_TASK_UPDATED, Time.current, account: account, task: task)
  end
end
