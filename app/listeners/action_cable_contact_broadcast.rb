module ActionCableContactBroadcast
  private

  def broadcast_message_to_agents_and_contact(account, tokens, event_name, message, data = message.push_event_data)
    # Shallow copies only: deep_dup would duplicate ActiveRecord objects (no id) and break job serialization.
    contact_data = data.dup
    contact_data[:content_attributes] = message.public_content_attributes
    previous_content_attributes = contact_data.dig(:previous_changes, :content_attributes) ||
                                  contact_data.dig(:previous_changes, 'content_attributes')
    if previous_content_attributes
      contact_data[:previous_changes] = contact_data[:previous_changes].dup
      contact_data[:previous_changes].delete('content_attributes')
      contact_data[:previous_changes][:content_attributes] = previous_content_attributes.map do |attributes|
        message.public_content_attributes(attributes)
      end
    end
    sessions = message_contact_inboxes(message.conversation, message)
    widget_tokens, client_tokens = split_contact_tokens(sessions)
    broadcast(account, tokens, event_name, data,
              widget: { tokens: widget_tokens, data: message.widget_push_event_data(contact_data) })
    broadcast(account, client_tokens, event_name, contact_data)
  end

  def broadcast_conversation_to_agents_and_contact(account, tokens, event_name, conversation, data = conversation.push_event_data)
    sessions = session_contact_inboxes(conversation.contact_inbox)
    widget_tokens, client_tokens = split_contact_tokens(sessions)
    widget_tokens = [] if event_name == Events::Types::CONVERSATION_UPDATED
    broadcast(account, tokens, event_name, data,
              widget: { tokens: widget_tokens, data: conversation.widget_push_event_data })
    return if client_tokens.blank?

    ::ActionCableBroadcastJob.perform_later(client_tokens.uniq, event_name,
                                            broadcast_payload(account, public_conversation_data(conversation, data)), public_contact_payload: true)
  end

  def public_conversation_data(conversation, data)
    last_message = conversation.messages.where(account_id: conversation.account_id).chat.last
    data.merge(messages: last_message ? [last_message.push_event_data.merge(content_attributes: last_message.public_content_attributes)] : [])
  end
end
