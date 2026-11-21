class Captain::Conversation::UsageLimitHandoff
  def initialize(conversation:)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  def perform
    @conversation.class.transaction { perform_handoff }
  end

  def perform_handoff
    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{@conversation.id}")
    routing = Captain::HandoffRouter.new(conversation: @conversation, assistant: @inbox.captain_assistant).plan
    transitioned = @conversation.pending?
    @conversation.bot_handoff!(routing: routing)
    note = create_unavailable_note(handoff: true)
    routing.append_to(note)
    record_usage_handoff(note) if transitioned
    Captain::ConversationEvents.handed_off(
      conversation: @conversation,
      assistant: @inbox.captain_assistant,
      source: Captain::ConversationEvents::Sources::USAGE_LIMIT,
      reason_category: :usage_limit,
      at: Time.current
    )
    Captain::Conversation::HandoffReply.new(
      @conversation, @inbox.captain_assistant, fallback: I18n.t('conversations.captain.handoff', locale: @conversation.account.locale)
    ).perform
  end

  def create_unavailable_note(handoff: false)
    @conversation.class.transaction { write_unavailable_note(handoff: handoff) }
  end

  private

  def record_usage_handoff(note)
    Captain::Decisions::Action.record(
      conversation: @conversation, assistant: @inbox.captain_assistant,
      decision_key: "usage_limit:#{@conversation.id}:#{note.id}", kind: 'handoff', origin: 'rule', trigger: 'usage_limit',
      anchor_message: note, reason_code: 'usage_limit_handoff', reason_text: note.content
    )
  end

  def record_unavailable(note)
    Captain::Decisions::Action.record(
      conversation: @conversation, assistant: @inbox.captain_assistant, decision_key: "unavailable:#{@conversation.id}:#{note.id}",
      kind: 'reply', outcome: 'skipped', origin: 'rule', trigger: 'usage_limit', anchor_message: note,
      reason_code: 'captain_unavailable', reason_text: note.content
    )
  end

  def write_unavailable_note(handoff:)
    assistant = @inbox.captain_assistant
    reason = @inbox.captain_paused_reason
    return if assistant.blank? || (!handoff && reason.blank?)

    note_key = reason.present? ? "captain.notes.unavailable.#{reason}" : 'captain.notes.handoff_usage_limit'
    attributes = handoff ? { captain_handoff: { reason_category: 'usage_limit', source: 'usage_limit' } } : {}
    note = @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: @conversation.account.id,
      inbox_id: @inbox.id,
      content: I18n.t(note_key, assistant: assistant.name, locale: @conversation.account.locale),
      content_attributes: attributes
    )
    record_unavailable(note) unless handoff
    note
  end

  private :perform_handoff
end
