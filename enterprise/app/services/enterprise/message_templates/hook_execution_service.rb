module Enterprise::MessageTemplates::HookExecutionService
  def trigger_templates
    super
    return unless captain_conversation_message?

    # Eligibility is demand-level: every inbound customer message in a
    # Captain-connected inbox counts, including conversations a human grabbed
    # first or that arrive while the account is over its usage limit —
    # otherwise the coverage denominator only ever contains conversations
    # Captain was already about to answer.
    track_captain_eligibility
    return captain_unavailable unless inbox.captain_active?
    return unless conversation.pending?

    Captain::Conversation::ResponseSchedulerService.new(message: message).perform
  end

  def should_send_greeting?
    return false if captain_handling_conversation?

    super
  end

  def should_send_out_of_office_message?
    return false if captain_handling_conversation?

    super
  end

  def should_send_email_collect?
    return false if captain_handling_conversation?

    super
  end

  private

  def track_captain_eligibility
    return unless conversation.account.feature_enabled?('captain_integration_v2')

    Captain::ConversationOutcomeTracker.new(
      conversation: conversation,
      assistant: inbox.captain_assistant
    ).record_eligibility(at: message.created_at)
  end

  def captain_conversation_message?
    message.captain_response_triggering? && captain_assistant_configured? && !inbox.external_bot_active?
  end

  # Captain is paused (no AI key, or no responses left). A pending conversation is handed off; one
  # that was never taken gets a single note on its first customer message so agents know why.
  def captain_unavailable
    return perform_handoff if conversation.pending?

    create_unavailable_note if first_customer_message?
  end

  def first_customer_message?
    conversation.messages.incoming.where(private: false).count == 1
  end

  def create_unavailable_note
    assistant = inbox.captain_assistant
    reason = inbox.captain_paused_reason
    return if assistant.blank? || reason.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      content: I18n.t("captain.notes.unavailable.#{reason}", assistant: assistant.name, locale: conversation.account.locale)
    )
  end

  def perform_handoff
    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      content: handoff_message_content
    )
    create_unavailable_note
    conversation.bot_handoff!
    Captain::ConversationEvents.handed_off(
      conversation: conversation,
      assistant: inbox.captain_assistant,
      source: Captain::ConversationEvents::Sources::USAGE_LIMIT,
      reason_category: :usage_limit,
      at: Time.current
    )
    send_out_of_office_message_after_handoff
  end

  def handoff_message_content
    inbox.captain_assistant&.config&.[]('handoff_message').presence ||
      I18n.with_locale(conversation.account.locale) { I18n.t('conversations.captain.handoff') }
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def captain_handling_conversation?
    conversation.pending? && captain_assistant_configured?
  end

  def captain_assistant_configured?
    inbox.captain_assistant.present?
  end
end
