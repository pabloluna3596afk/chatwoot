class Captain::Tools::Copilot::SummarizeConversationService < Captain::Tools::BaseTool
  include Captain::Copilot::ConversationAccess

  MAX_MESSAGE_CHARS = 2_000

  def self.name
    'summarize_conversation'
  end

  description <<~DESCRIPTION.strip
    Read a conversation transcript with message IDs, timestamps, and authors for citations. Private notes are excluded.
    Only conversations available to the current user are returned.
  DESCRIPTION

  parameters type: 'object', required: %w[conversation_id], additionalProperties: false,
             properties: {
               conversation_id: { type: 'integer', minimum: 1, description: 'Conversation display ID' },
               limit: { type: 'integer', minimum: 1, maximum: 100, description: 'Number of latest messages; defaults to 20' }
             }

  def execute(conversation_id:, limit: 20)
    validate_limit!(limit)
    conversation = accessible_conversation(account: @assistant.account, user: @user, display_id: conversation_id)
    return 'Conversation not found' if conversation.blank?

    messages = conversation.messages.where(private: false).where.not(message_type: %i[activity template])
    total = messages.count
    selected = messages.includes(:sender).order(created_at: :desc, id: :desc).limit(limit).to_a.reverse
    omitted_count = total - selected.length
    output = ["Conversation ##{conversation.display_id}", "+#{omitted_count} earlier messages not included"] if omitted_count.positive?
    output ||= ["Conversation ##{conversation.display_id}"]
    selected.each { |message| output << format_message(message) }
    output.join("\n")
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage')
  end

  private

  def validate_limit!(limit)
    return if limit.is_a?(Integer) && limit.between?(1, 100)

    raise ArgumentError, 'limit must be an integer from 1 to 100'
  end

  def format_message(message)
    author = message.sender&.name || message.sender_type || 'Unknown author'
    content = message.content_for_llm.to_s.truncate(MAX_MESSAGE_CHARS)
    "[message_id=#{message.id} at=#{message.created_at.iso8601} author=#{author}] #{content}"
  end
end
