class Captain::Tools::Copilot::SearchConversationsService < Captain::Tools::BaseTool
  include Captain::Copilot::ConversationAccess

  def self.name
    'search_conversation'
  end
  description <<~DESCRIPTION.strip
    Search conversations by filters. For latest or most recent, use order_by=last_activity_at, direction=desc, limit=1.
    If filtered results are empty, repeat once without filters before concluding.
  DESCRIPTION

  parameters type: 'object', additionalProperties: false,
             properties: {
               status: { type: 'string', description: 'Status: open, resolved, pending, or snoozed' },
               contact_id: { type: 'number', description: 'Contact id' },
               priority: { type: 'string', description: 'Priority: low, medium, high, or urgent' },
               labels: { type: 'string', description: 'Available labels' },
               order_by: { type: 'string', enum: %w[last_activity_at created_at] },
               direction: { type: 'string', enum: %w[asc desc] },
               limit: { type: 'integer', minimum: 1, maximum: 100,
                        description: 'Defaults to 10 when order_by is set' }
             }

  # RubyLLM exposes each keyword as a separate JSON Schema tool parameter.
  # rubocop:disable Metrics/ParameterLists
  def execute(status: nil, contact_id: nil, priority: nil, labels: nil, order_by: nil, direction: nil, limit: nil)
    direction, result_limit = normalized_order(order_by, direction, limit)
    conversations = get_conversations(status, contact_id, priority, labels)
    conversations = order_conversations(conversations, order_by, direction) if order_by.present?

    return 'No conversations found' unless conversations.exists?

    format_conversations(conversations, result_limit)
  rescue ArgumentError => e
    { error: e.message }
  end
  # rubocop:enable Metrics/ParameterLists

  def active?
    user_has_permission('conversation_manage') ||
      user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage')
  end

  private

  def normalized_order(order_by, direction, limit)
    validate_order!(order_by, direction, limit)
    [direction || 'desc', order_by.present? ? (limit || 10) : 100]
  end

  def validate_order!(order_by, direction, limit)
    validate_order_field!(order_by)
    validate_direction!(order_by, direction)
    validate_limit!(order_by, limit)
  end

  def validate_order_field!(order_by)
    return if order_by.nil?
    return if %w[last_activity_at created_at].include?(order_by)

    raise ArgumentError, 'order_by must be last_activity_at or created_at'
  end

  def validate_direction!(order_by, direction)
    return if direction.nil?
    raise ArgumentError, 'direction requires order_by' if order_by.nil?
    return if %w[asc desc].include?(direction)

    raise ArgumentError, 'direction must be asc or desc'
  end

  def validate_limit!(order_by, limit)
    return if limit.nil?
    raise ArgumentError, 'limit requires order_by' if order_by.nil?
    return if limit.is_a?(Integer) && limit.between?(1, 100)

    raise ArgumentError, 'limit must be an integer from 1 to 100'
  end

  def format_conversations(conversations, result_limit)
    total_count = conversations.count
    result_summary = if total_count > result_limit
                       "Found #{total_count} conversations (showing first #{result_limit})"
                     else
                       "Total number of conversations: #{total_count}"
                     end
    records = conversations.limit(result_limit).map { |conversation| conversation_summary(conversation) }.join("\n---\n")

    "#{result_summary}\n#{records}"
  end

  def order_conversations(conversations, order_by, direction)
    table = Conversation.arel_table
    primary_order = direction == 'asc' ? table[order_by].asc.nulls_last : table[order_by].desc.nulls_last
    conversations.order(primary_order, table[:id].public_send(direction))
  end

  def conversation_summary(conversation)
    inbox = conversation.inbox&.name || 'No inbox'
    metadata = ["Conversation ##{conversation.display_id}", "status: #{conversation.status}", "inbox: #{inbox}",
                "last_activity_at: #{conversation.last_activity_at&.iso8601}"].join(' | ')
    "#{metadata}\n#{conversation.to_llm_text(include_contact_details: true, include_private_messages: true)}"
  end

  def get_conversations(status, contact_id, priority, labels)
    conversations = permissible_conversations
    conversations = conversations.where(contact_id: contact_id) if contact_id.present?
    conversations = conversations.where(status: status) if valid_status?(status)
    conversations = conversations.where(priority: priority) if valid_priority?(priority)
    conversations = conversations.tagged_with(labels, any: true) if labels.present?
    conversations
  end

  def valid_status?(status)
    status.present? && Conversation.statuses.key?(status)
  end

  def valid_priority?(priority)
    priority.present? && Conversation.priorities.key?(priority)
  end

  def permissible_conversations
    accessible_conversations(account: @assistant.account, user: @user)
  end
end
