class Captain::Copilot::Resources::Conversations < Captain::Copilot::Resources::BaseResource
  NAME = 'conversations'.freeze
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
  DATE_FIELDS = %w[created_at last_activity_at].freeze
  FILTERS = Captain::Copilot::Resources::BaseResource::CONVERSATION_FILTERS.merge(contact_id: { type: 'integer', minimum: 1 }).freeze
  GROUPS = %w[status priority inbox assignee team label].freeze

  def scope
    accessible = accessible_conversations(account: @account, user: @user)
    Conversations::PermissionFilterService.new(accessible, @user, @account).perform
  end

  def filter(relation, filters)
    relation = relation.where(filters.slice('status', 'priority', 'inbox_id', 'team_id', 'contact_id'))
    if filters.key?('assignee_id')
      assignee_id = filters['assignee_id'] == 'me' ? @user&.id : filters['assignee_id']
      assignee_id = nil if filters['assignee_id'] == 'unassigned'
      relation = relation.where(assignee_id: assignee_id)
    end
    relation = relation.tagged_with(filters['labels'], any: true) if filters['labels'].present?
    custom_attribute_filter(relation, filters, 'conversation_attribute')
  end

  def counts_by(relation, group)
    case group
    when 'status', 'priority' then column_counts(relation, group)
    when 'inbox' then column_counts(relation, :inbox_id, names: @account.inboxes)
    when 'assignee' then column_counts(relation, :assignee_id, names: @account.users)
    when 'team' then column_counts(relation, :team_id, names: @account.teams)
    when 'label' then label_counts(relation)
    end
  end
end
