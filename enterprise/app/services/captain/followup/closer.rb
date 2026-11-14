# Shared inactivity close, called under the caller's conversation lock.
class Captain::Followup::Closer
  def initialize(conversation, assistant, now: Time.current, note_key: 'captain.followup.closed_note', send_resolution_message: true)
    @conversation = conversation
    @assistant = assistant
    @now = now
    @note_key = note_key
    @send_resolution_message = send_resolution_message
  end

  def perform
    Current.executed_by = assistant
    conversation.with_captain_activity_context(reason: 'no reply to the follow-up', reason_type: :inference) do
      create_note
      create_resolution_message if send_resolution_message
      conversation.resolved!
      mark_closed
    end
    :closed
  end

  private

  attr_reader :conversation, :assistant, :now, :note_key, :send_resolution_message

  def account = conversation.account
  def locale = account.locale

  def create_note
    conversation.messages.create!(
      message_type: :outgoing, private: true, sender: assistant, account_id: account.id,
      inbox_id: conversation.inbox_id, content: I18n.t(note_key, locale: locale, assistant: assistant.name)
    )
  end

  # Same optional goodbye the assistant already sends when it closes for inactivity, only inside the window.
  def create_resolution_message
    return unless assistant.send_inactivity_resolution_message? && conversation.can_reply?

    conversation.messages.create!(
      message_type: :outgoing, sender: assistant, account_id: account.id, inbox_id: conversation.inbox_id,
      content: assistant.config['resolution_message'].presence || I18n.t('conversations.activity.auto_resolution_message', locale: locale)
    )
  end

  # What the re-engagement later needs to find the conversation.
  def mark_closed
    attributes = conversation.additional_attributes || {}
    conversation.update!(additional_attributes: attributes.merge(
      Captain::Followup::Reengager::STATE_KEY => { 'closed_at' => now.utc.iso8601, 'assistant_id' => assistant.id }
    ))
  end
end
