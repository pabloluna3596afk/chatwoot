class Captain::Decisions::Access
  def self.visible_anchor?(user, message)
    return false unless user.is_a?(User) && message && !message.content_attributes['deleted']
    return true unless message.private?

    Conversations::PrivateNoteVisibility.allowed?(user: user, message: message, conversation: message.conversation)
  end
end
