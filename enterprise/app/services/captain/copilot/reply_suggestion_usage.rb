module Captain::Copilot::ReplySuggestionUsage
  private

  def generate_metered_reply(conversation, target_message)
    Llm::UsageContext.with(
      account: @account,
      bucket: :copilot,
      feature: 'copilot_reply_suggestion',
      context: { conversation_id: conversation.id, message_id: target_message.id }
    ) { generate_reply(conversation) }
  end
end
