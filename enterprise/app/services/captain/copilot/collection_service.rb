class Captain::Copilot::CollectionService
  MAX_TOOL_CALLS = 5

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def create(resource:, filters:, group_by: nil, aggregate: nil)
    validate_input!(filters, group_by, aggregate)

    filters = filters.deep_stringify_keys
    aggregate = aggregate&.deep_stringify_keys
    validate_aggregate!(aggregate)
    selector = Captain::Copilot::Resources.build(resource, account: @account, user: @user)
    as_of = Time.current
    matching = selector.matching(filters, as_of: as_of)
    result = { resource: resource, total: matching.count, as_of: as_of.iso8601,
               aggregate: selector.aggregate_value(matching, aggregate) }
    add_groups(result, selector, matching, filters, group_by)
  end

  private

  def validate_input!(filters, group_by, aggregate)
    raise ArgumentError, 'filters must be an object' unless filters.is_a?(Hash)
    raise ArgumentError, 'group_by must be a string' unless group_by.nil? || group_by.is_a?(String)
    raise ArgumentError, 'aggregate must be an object' unless aggregate.nil? || aggregate.is_a?(Hash)
  end

  def validate_aggregate!(aggregate)
    return unless aggregate && (aggregate.keys - %w[function key]).any?

    raise ArgumentError, 'aggregate only accepts function and key'
  end

  def add_groups(result, selector, matching, filters, group_by)
    return result unless group_by

    result[:group_by] = group_by
    date_field = filters.fetch('date_field', selector.class::DATE_FIELDS.first)
    result[:groups] = selector.group_counts(matching, group_by, date_field: date_field)
    result
  end
end
