class Captain::Decisions::ControlRecording
  def initialize(conversation, assistant)
    @conversation = conversation
    @assistant = assistant
  end

  def record(kind, key, trigger:, anchor: nil, reason_text: nil)
    Captain::Decisions::Action.record(
      conversation: @conversation, assistant: @assistant, kind: kind, origin: 'rule', trigger: trigger,
      decision_key: "#{kind}:#{@conversation.id}:#{key}", anchor_message: anchor, reason_code: kind, reason_text: reason_text
    )
  end

  def self.transition(conversation)
    return unless control_changed?(conversation)

    Captain::Decisions::Recorder.capture(conversation) do
      assistant = conversation.inbox.captain_assistant
      next unless assistant

      kind = conversation.assignee_id.present? ? 'human_control' : 'disengage'
      new(conversation, assistant).record(kind, "transition:#{conversation.updated_at.utc.iso8601(6)}", trigger: 'assignment')
    end
  end

  def self.control_changed?(conversation)
    return false if conversation.captain_control_event || Current.executed_by.is_a?(Captain::Assistant)
    return false if conversation.saved_change_to_captain_handed_off_at? && conversation.captain_handed_off_at.present?
    return false unless previously_handled?(conversation)

    !conversation.captain_attended? && ownership_changed?(conversation)
  end

  def self.previously_handled?(conversation)
    conversation.ai_assignee_type_before_last_save == 'Captain::Assistant' ||
      (conversation.captain_handed_off_at_before_last_save.present? && conversation.saved_change_to_assignee_id?)
  end

  def self.ownership_changed?(conversation)
    conversation.saved_change_to_assignee_id? || conversation.saved_change_to_ai_assignee_type? || conversation.saved_change_to_status?
  end

  def self.with_human_context(message)
    conversation = message.conversation
    previous_user = Current.user
    previous_executed_by = Current.executed_by
    conversation.captain_control_source = response_source(message, previous_executed_by)
    conversation.captain_control_event = conversation.captain_control_source[:type] == 'user' ? 'human_control' : 'disengage'
    Current.user = nil
    Current.executed_by = nil
    yield
  ensure
    conversation.captain_control_event = nil
    conversation.captain_control_source = nil
    Current.user = previous_user
    Current.executed_by = previous_executed_by
  end

  def self.response_source(message, executor)
    return { type: 'automation_rule', name: executor.name } if executor.is_a?(AutomationRule)
    return { type: 'user', name: message.sender.name } if message.sender.is_a?(User)
    return { type: 'external_echo' } if message.content_attributes['external_echo']

    { type: 'system' }
  end

  def self.record_response_control(message, anchor: nil)
    conversation = message.conversation
    Captain::Decisions::Recorder.capture(conversation) do
      assistant = conversation.inbox.captain_assistant
      next unless assistant

      kind = conversation.captain_control_event
      new(conversation, assistant).record(kind, message.id, trigger: kind == 'human_control' ? 'human_action' : 'assignment', anchor: anchor)
    end
  end

  def self.open_human_reply(message)
    record_response_control(message, anchor: message) if message.conversation.saved_change_to_assignee_id?
  end

  def self.human_activity(message)
    conversation = message.conversation
    decision = record_response_control(message)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
        content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale),
        content_attributes: { activity: { type: 'captain_control_changed', event: conversation.captain_control_event,
                                          source: conversation.captain_control_source } } },
      decision&.decision_key
    )
  end
end
