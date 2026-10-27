class Captain::Copilot::CollectionService
  MAX_TOOL_CALLS = 5

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def create(resource:, filters:, group_by: nil)
    raise ArgumentError, 'filters must be an object' unless filters.is_a?(Hash)
    raise ArgumentError, 'group_by must be a string' unless group_by.nil? || group_by.is_a?(String)

    filters = filters.deep_stringify_keys
    selector = Captain::Copilot::Resources.build(resource, account: @account, user: @user)
    as_of = Time.current
    matching = selector.matching(filters, as_of: as_of)
    result = { resource: resource, total: matching.count, as_of: as_of.iso8601 }
    if group_by
      result[:group_by] = group_by
      date_field = filters.fetch('date_field', selector.class::DATE_FIELDS.first)
      result[:groups] = selector.group_counts(matching, group_by, date_field: date_field)
    end
    result
  end
end
