class BackgroundTasks::Sources
  LIMIT = 20
  # Add a module by appending its source class here.
  # Implement .tasks(account, user), returning active tasks and recent results.
  CLASSES = [Whatsapp::TemplateBackgroundTask].freeze

  def self.tasks(account, user)
    tasks = CLASSES.flat_map { |source| source.tasks(account, user) }
    active, results = tasks.partition { |task| task[:status] == 'running' }
    active + results.sort_by { |task| task[:updated_at] }.reverse.first(LIMIT)
  end
end
