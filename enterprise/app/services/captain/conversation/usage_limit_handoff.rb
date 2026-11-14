class Captain::Conversation::UsageLimitHandoff
  def initialize(conversation:)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  def perform
    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{@conversation.id}")
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account.id,
      inbox_id: @inbox.id,
      content: handoff_message_content
    )
    create_unavailable_note
    @conversation.bot_handoff!
    Captain::ConversationEvents.handed_off(
      conversation: @conversation,
      assistant: @inbox.captain_assistant,
      source: Captain::ConversationEvents::Sources::USAGE_LIMIT,
      reason_category: :usage_limit,
      at: Time.current
    )
    send_out_of_office_message_after_handoff
  end

  def create_unavailable_note
    assistant = @inbox.captain_assistant
    reason = @inbox.captain_paused_reason
    return if assistant.blank? || reason.blank?

    @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: @conversation.account.id,
      inbox_id: @inbox.id,
      content: I18n.t("captain.notes.unavailable.#{reason}", assistant: assistant.name, locale: @conversation.account.locale)
    )
  end

  private

  def handoff_message_content
    @inbox.captain_assistant&.config&.[]('handoff_message').presence ||
      I18n.with_locale(@conversation.account.locale) { I18n.t('conversations.captain.handoff') }
  end

  def send_out_of_office_message_after_handoff
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end
end
