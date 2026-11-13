# When the current support episode of a conversation started: the moment it was last resolved.
class Captain::Conversation::EpisodeBoundary
  LOOKBACK = 100

  def self.last_resolved_at(conversation)
    conversation.messages.where(message_type: :activity).reorder(created_at: :desc, id: :desc).limit(LOOKBACK)
                .find { |message| resolved_activity?(message) }&.created_at
  end

  def self.resolved_activity?(message)
    activity = message.content_attributes.to_h['activity'].to_h
    activity['type'] == 'conversation_status_changed' && activity['status'] == 'resolved'
  end
end
