class Captain::Conversation::UsageLimitHandoff
  def initialize(conversation:)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  def perform
    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{@conversation.id}")
    @conversation.bot_handoff!
    create_unavailable_note(handoff: true)
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
    assistant = @inbox.captain_assistant
    reason = @inbox.captain_paused_reason
    return if assistant.blank? || (!handoff && reason.blank?)

    note_key = reason.present? ? "captain.notes.unavailable.#{reason}" : 'captain.notes.handoff_usage_limit'
    attributes = handoff ? { captain_handoff: { reason_category: 'usage_limit', source: 'usage_limit' } } : {}
    @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: @conversation.account.id,
      inbox_id: @inbox.id,
      content: I18n.t(note_key, assistant: assistant.name, locale: @conversation.account.locale),
      content_attributes: attributes
    )
  end
end
