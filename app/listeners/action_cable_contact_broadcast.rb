module ActionCableContactBroadcast
  private

  def broadcast_message_to_agents_and_contact(account, tokens, event_name, message, data = message.push_event_data)
    contact_tokens = contact_tokens(message.conversation.contact_inbox, message)
    broadcast(account, tokens - contact_tokens, event_name, data)
    return if contact_tokens.blank?

    contact_data = data.deep_dup
    contact_data[:content_attributes] = message.public_content_attributes
    previous_content_attributes = contact_data.dig(:previous_changes, :content_attributes) ||
                                  contact_data.dig(:previous_changes, 'content_attributes')
    if previous_content_attributes
      contact_data[:previous_changes].delete('content_attributes')
      contact_data[:previous_changes][:content_attributes] = previous_content_attributes.map do |attributes|
        message.public_content_attributes(attributes)
      end
    end
    broadcast(account, contact_tokens, event_name, contact_data)
  end

  def broadcast_conversation_to_agents_and_contact(account, tokens, event_name, conversation, data = conversation.push_event_data)
    contact_tokens = contact_inbox_tokens(conversation.contact_inbox)
    broadcast(account, tokens - contact_tokens, event_name, data)
    return if contact_tokens.blank?

    contact_data = data.deep_dup
    last_message = conversation.messages.where(account_id: account.id).chat.last
    contact_data[:messages] = if last_message
                                [last_message.push_event_data.merge(content_attributes: last_message.public_content_attributes)]
                              else
                                []
                              end
    broadcast(account, contact_tokens, event_name, contact_data)
  end
end
