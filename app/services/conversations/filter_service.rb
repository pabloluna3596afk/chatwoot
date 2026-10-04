class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  # The status filter follows what the agent sees: a conversation Captain attends counts as open (Conversation.displayed_as).
  def default_filter(query_hash, filter_operator_value)
    return super unless query_hash[:attribute_key] == 'status' && %w[equal_to not_equal_to].include?(query_hash[:filter_operator])

    displayed = Array(query_hash['values']).map { |status| displayed_status_condition(status.to_s) }.join(' OR ')
    condition = query_hash[:filter_operator] == 'equal_to' ? "(#{displayed})" : "NOT (#{displayed})"
    "#{condition} #{query_hash[:query_operator]}"
  end

  def displayed_status_condition(status)
    case status
    when 'all' then 'TRUE'
    when 'open' then "(conversations.status = #{Conversation.statuses[:open]} OR #{Conversation::CAPTAIN_ATTENDED_SQL})"
    when 'pending' then "(conversations.status = #{Conversation.statuses[:pending]} AND NOT #{Conversation::CAPTAIN_ATTENDED_SQL})"
    else plain_status_condition(status)
    end
  end

  def plain_status_condition(status)
    value = Conversation.statuses[status]
    raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'status') if value.nil?

    "conversations.status = #{value}"
  end

  def set_count_for_all_conversations
    [
      @conversations.assigned_to(@user).count,
      @conversations.queue_unassigned.count,
      @conversations.with_human_assignee.count,
      @conversations.count
    ]
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, assigned_count, all_count = set_count_for_all_conversations

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    # :messages is deliberately not preloaded: the list payload fetches messages through
    # scoped queries (last message, last_non_activity_message), which bypass the preload.
    conversations = @account.conversations.includes(
      :taggings, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team,
      :contact_inbox
    ).preload(
      inbox: :channel,
      ai_assignee: { avatar_attachment: [:blob] }
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account,
      plan_hint_selective_filter: label_filter_present?
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    Conversations::Sort.apply(@conversations, @params[:sort_by], account: @account).page(current_page)
  end

  def filter_values(query_hash)
    if query_hash['attribute_key'] == 'campaign_id'
      return @account.campaigns.where(display_id: query_hash['values']).pluck(:id)
    end

    super
  end

  private

  # The planner hint only pays off when the label condition positively narrows the
  # result set: `equal_to` joined by AND. Negative/presence operators or an OR in the
  # payload leave the result broad, where the inbox index is the better driver.
  def label_filter_present?
    payload = @params[:payload].to_a
    return false if payload.any? { |query_hash| query_hash[:query_operator].to_s.casecmp('or').zero? }

    payload.any? { |query_hash| query_hash[:attribute_key] == 'labels' && query_hash[:filter_operator] == 'equal_to' }
  end
end

Conversations::FilterService.prepend_mod_with('Conversations::FilterService')
