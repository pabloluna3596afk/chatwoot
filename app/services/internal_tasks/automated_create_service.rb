class InternalTasks::AutomatedCreateService
  IDEMPOTENCY_TTL = 24.hours.to_i

  pattr_initialize [:conversation!, :source!, :params!]

  def perform
    parameters = AutomationRules::InternalTaskParameters.new(params, account: conversation.account)
    error = parameters.error
    error ||= 'create_internal_task: internal_tasks feature is disabled.' unless conversation.account.feature_enabled?('internal_tasks')
    return log_error(error) if error

    attributes = parameters.task_params(conversation)
    key = idempotency_key(attributes[:title])
    return unless Redis::Alfred.set(key, '1', nx: true, ex: IDEMPOTENCY_TTL)

    InternalTasks::CreateService.new(
      conversation: conversation, user: nil,
      params: attributes.merge(metadata: { created_by_type: 'system', source_type: source.class.name, source_id: source.id })
    ).perform
  end

  private

  def idempotency_key(title)
    "internal_task:#{source.class.name}:#{source.id}:#{conversation.id}:#{Digest::SHA256.hexdigest(title)}"
  end

  def log_error(error)
    Rails.logger.error(
      "[create_internal_task] source_type=#{source.class.name} rule_id=#{source.id} conversation_id=#{conversation.id}: #{error}"
    )
  end
end
