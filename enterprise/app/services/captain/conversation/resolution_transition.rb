# Every automatic closer serializes its final eligibility check and transition on the same row.
class Captain::Conversation::ResolutionTransition
  def self.perform(conversation, assistant, signal: false)
    conversation.with_lock do
      next unless eligible?(conversation, assistant)
      next if !signal && signal_active?(conversation)

      yield
    end
  end

  def self.eligible?(conversation, assistant)
    return false unless conversation.pending? && conversation.assignee_id.nil?
    return false if conversation.ai_assignee.present? && conversation.ai_assignee != assistant

    conversation.inbox.captain_assistant == assistant && !assistant.reload.inactive_conversation_resolution_disabled?
  end

  def self.signal_active?(conversation)
    state = conversation.additional_attributes[Captain::Conversation::CompletionSignal::KEY]
    state && Captain::Conversation::CompletionSignal::ACTIVE_STATUSES.include?(state['status'])
  end
end
