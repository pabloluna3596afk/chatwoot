class AutomationRules::InternalTaskParameters
  def initialize(params, account:)
    @account = account
    @data = params.first.with_indifferent_access if params.is_a?(Array) && params.one? && params.first.is_a?(Hash)
  end

  def error
    message = fields_error || assignee_error || due_in_error
    "create_internal_task: #{message}" if message
  end

  def task_params(conversation)
    {
      title: @data[:title],
      assigned_to_id: @data.fetch(:assignee_id, conversation.assignee_id),
      due_at: @data.key?(:due_in) ? (Time.current + snooze.duration).iso8601 : nil
    }
  end

  private

  def fields_error
    return 'requires one parameter hash with title.' unless @data
    return 'title must be non-empty text.' unless @data[:title].is_a?(String) && @data[:title].present?
    return 'unsupported parameters.' if (@data.keys - %w[title assignee_id due_in]).any?

    limit = InternalTask.columns_hash.fetch('title').limit
    "title must not exceed #{limit} characters." if limit && @data[:title].length > limit
  end

  def assignee_error
    return unless @data.key?(:assignee_id)

    id = @data[:assignee_id]
    return if id.is_a?(Integer) && @account.account_users.agent.exists?(user_id: id)

    'assignee_id must identify an agent of the account.'
  end

  def due_in_error
    return unless @data.key?(:due_in)

    due_in = @data[:due_in]
    return 'due_in requires a hash with duration and unit.' unless due_in.is_a?(Hash)
    return 'due_in requires only duration and unit.' unless due_in.keys.sort == %w[duration unit]

    snooze.error&.sub('snooze_conversation', 'due_in')
  end

  def snooze
    Conversations::SnoozeParameters.new(@data[:due_in])
  end
end
