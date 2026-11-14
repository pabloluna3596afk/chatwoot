# The customer owes the reply when the last public message (nudges aside) is Captain's.
class Captain::Conversation::Turn
  SCAN = 10

  def self.last_message(conversation)
    conversation.messages.where(private: false, message_type: %i[incoming outgoing])
                .reorder(created_at: :desc, id: :desc).limit(SCAN)
                .find { |message| message.content_attributes.to_h['captain_followup'] != 'nudge' }
  end

  def self.awaiting_customer?(conversation, assistant)
    message = last_message(conversation)
    message.present? && message.outgoing? && message.sender_type == 'Captain::Assistant' && message.sender_id == assistant.id
  end
end
