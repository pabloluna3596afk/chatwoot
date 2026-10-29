class Captain::Tools::Copilot::SearchConversationsService < Captain::Tools::BaseTool
  include Captain::Copilot::ConversationAccess

  FILTER_ERROR_MESSAGES = {
    status: 'status must be open, resolved, pending, or snoozed',
    priority: 'priority must be low, medium, high, or urgent',
    contact_id: 'contact_id must be a positive integer',
    labels: 'labels must be a string',
    inbox_id: 'inbox_id must be a positive integer',
    team_id: 'team_id must be a positive integer',
    assignee_id: 'assignee_id must be a positive integer, me, or unassigned'
  }.freeze
  FILTER_VALIDATORS = {
    status: ->(value) { Conversation.statuses.key?(value) },
    priority: ->(value) { Conversation.priorities.key?(value) },
    contact_id: ->(value) { value.is_a?(Integer) && value.positive? },
    labels: ->(value) { value.is_a?(String) && value.present? },
    inbox_id: ->(value) { value.is_a?(Integer) && value.positive? },
    team_id: ->(value) { value.is_a?(Integer) && value.positive? },
    assignee_id: ->(value) { %w[me unassigned].include?(value) || (value.is_a?(Integer) && value.positive?) }
  }.freeze

  def self.name
    'search_conversation'
  end
  description <<~DESCRIPTION.strip
    Search conversations by status, priority, labels, date range, inbox, agent, or team. Date values accept ISO 8601 or today, yesterday, last_7_days, last_30_days in the account timezone. Use assignee_id=me or unassigned when appropriate. For example: "the last five conversations for agent X" or "conversations received this week by inbox".
    For latest or most recent, use order_by=last_activity_at, direction=desc, limit=1.
    If filtered results are empty, repeat once without filters before concluding.
  DESCRIPTION

  parameters type: 'object', additionalProperties: false,
             properties: {
               status: { type: 'string', enum: Conversation.statuses.keys, description: 'Conversation status' },
               contact_id: { type: 'number', description: 'Contact id' },
               priority: { type: 'string', enum: Conversation.priorities.keys, description: 'Conversation priority' },
               labels: { type: 'string', description: 'Available labels' },
               created_after: { type: 'string', description: 'ISO 8601 or today, yesterday, last_7_days, last_30_days; account timezone' },
               created_before: { type: 'string', description: 'Exclusive ISO 8601 or relative upper bound; account timezone' },
               last_activity_after: { type: 'string', description: 'ISO 8601 or relative date; account timezone' },
               last_activity_before: { type: 'string', description: 'Exclusive ISO 8601 or relative upper bound; account timezone' },
               inbox_id: { type: 'integer', minimum: 1, description: 'Inbox id' },
               assignee_id: { type: %w[integer string], description: 'Agent id, me, or unassigned' },
               team_id: { type: 'integer', minimum: 1, description: 'Team id' },
               order_by: { type: 'string', enum: %w[last_activity_at created_at] },
               direction: { type: 'string', enum: %w[asc desc] },
               limit: { type: 'integer', minimum: 1, maximum: 100,
                        description: 'Defaults to 10 when order_by is set' }
             }

  # RubyLLM exposes each keyword as a separate JSON Schema tool parameter.
  # rubocop:disable Metrics/ParameterLists
  def execute(status: nil, contact_id: nil, priority: nil, labels: nil, created_after: nil, created_before: nil,
              last_activity_after: nil, last_activity_before: nil, inbox_id: nil, assignee_id: nil, team_id: nil,
              order_by: nil, direction: nil, limit: nil)
    filters = { status: status, contact_id: contact_id, priority: priority, labels: labels, inbox_id: inbox_id,
                assignee_id: assignee_id, team_id: team_id, created_after: created_after,
                created_before: created_before, last_activity_after: last_activity_after,
                last_activity_before: last_activity_before }.compact
    validate_filters!(filters)
    direction, result_limit = normalized_order(order_by, direction, limit)
    conversations = get_conversations(filters)
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

  def get_conversations(filters)
    conversations = permissible_conversations.where(filters.slice(:contact_id, :status, :priority, :inbox_id, :team_id))
    conversations = filter_assignee(conversations, filters[:assignee_id]) if filters[:assignee_id].present?
    conversations = conversations.tagged_with(filters[:labels], any: true) if filters[:labels].present?
    conversations = filter_date(conversations, 'created_at', filters[:created_after], filters[:created_before])
    filter_date(conversations, 'last_activity_at', filters[:last_activity_after], filters[:last_activity_before])
  end

  def filter_assignee(conversations, assignee_id)
    return conversations.where(assignee_id: @user.id) if assignee_id == 'me' && @user.present?
    return conversations.none if assignee_id == 'me'
    return conversations.where(assignee_id: nil) if assignee_id == 'unassigned'

    conversations.where(assignee_id: assignee_id)
  end

  def filter_date(conversations, field, after_value, before_value)
    after_at, before_at = date_filter.range(after_value, before_value)
    column = Conversation.arel_table[field]
    conversations = conversations.where(column.gteq(after_at)) if after_at
    conversations = conversations.where(column.lt(before_at)) if before_at
    conversations
  end

  def date_filter
    @date_filter ||= Captain::Copilot::DateFilter.new(
      timezone: @assistant.account.reporting_timezone.presence || Time.zone.name
    )
  end

  def validate_filters!(filters)
    FILTER_VALIDATORS.each do |key, validator|
      raise ArgumentError, FILTER_ERROR_MESSAGES.fetch(key) if filters.key?(key) && !validator.call(filters[key])
    end
  end

  def permissible_conversations
    accessible_conversations(account: @assistant.account, user: @user)
  end
end
