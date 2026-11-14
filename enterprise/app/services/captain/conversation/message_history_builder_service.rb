class Captain::Conversation::MessageHistoryBuilderService
  RESOLUTION_MARKER = '<conversation_boundary status="resolved" />'.freeze

  pattr_initialize [:conversation!, { pilot_rules: true }]

  def perform
    return build(conversation_messages_for_context) unless pilot_history?

    window = Captain::Conversation::HistoryWindow.new(conversation_messages_for_context).perform
    log_window(window)
    build(window.messages, image_message_ids: window.image_message_ids)
  end

  private

  def build(messages, image_message_ids: nil)
    messages.filter_map do |message|
      message_hash = message_hash_for_context(message, include_images: image_message_ids.nil? || image_message_ids.include?(message.id))
      next if message_hash.blank?

      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?
      message_hash
    end
  end

  def pilot_history?
    pilot_rules && Captain::Pilot.enabled?(conversation.account)
  end

  def log_window(window)
    Rails.logger.info(
      "[CAPTAIN][Context] event=history_built conversation_id=#{conversation.id} total=#{window.total} " \
      "kept=#{window.messages.size} image_messages=#{window.image_message_ids.size} capped=#{window.capped}"
    )
  end

  def conversation_messages_for_context
    conversation.messages
                .where(private: false, message_type: [:incoming, :outgoing, :activity])
                .reorder(created_at: :asc, id: :asc)
  end

  def message_hash_for_context(message, include_images:)
    return activity_message_hash(message) if message.message_type == 'activity'

    content = prepare_multimodal_message_content(message, include_images: include_images)
    return if content.blank?

    content = prefix_human_content(content) if pilot_history? && message.outgoing? && !message.private && message.sender_type == 'User'

    {
      content: content,
      role: determine_role(message)
    }
  end

  def activity_message_hash(message)
    return unless Captain::Conversation::EpisodeBoundary.resolved_activity?(message)

    {
      content: RESOLUTION_MARKER,
      role: 'assistant'
    }
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prefix_human_content(content)
    return "[Human agent]: #{content}" unless content.is_a?(Array)

    text = content.find { |part| part[:type] == 'text' }
    if text
      text[:text] = "[Human agent]: #{text[:text]}"
    else
      content.unshift(type: 'text', text: '[Human agent]: (attachment)')
    end
    content
  end

  def prepare_multimodal_message_content(message, include_images:)
    if message.outgoing? && message.sender_type == 'Captain::Assistant' && !message.deleted
      message_attributes = message.additional_attributes.to_h
      response_parts_attribute = Captain::Assistant::ResponseParts::MESSAGE_ATTRIBUTE_KEY
      if message_attributes.key?(response_parts_attribute)
        return Captain::Assistant::ResponseParts.new(message_attributes[response_parts_attribute]).plain_text.presence
      end
    end

    Captain::OpenAiMessageBuilderService.new(message: message, include_images: include_images).generate_content
  end
end
