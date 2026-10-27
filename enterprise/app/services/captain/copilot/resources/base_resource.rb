class Captain::Copilot::Resources::BaseResource
  include Captain::Copilot::ConversationAccess

  PERIODS = { 'day' => '%Y-%m-%d', 'week' => 'week of %Y-%m-%d', 'month' => '%Y-%m', 'year' => '%Y' }.freeze
  MAX_GROUPS = 100
  MAX_RANGE = 366.days
  RELATIVE_RANGE_BUILDERS = {
    'this_month' => ->(now) { [now.beginning_of_month, now.next_month.beginning_of_month] },
    'last_month' => ->(now) { [now.prev_month.beginning_of_month, now.beginning_of_month] },
    'last_7_days' => ->(now) { [now.to_date - 6.days, now.to_date + 1.day] },
    'yesterday_today' => ->(now) { [now.to_date - 1.day, now.to_date + 1.day] }
  }.freeze

  DATE_FILTERS = {
    since: { type: 'string', description: 'ISO 8601 date or timestamp, inclusive, in the account timezone' },
    before: { type: 'string', description: 'ISO 8601 date or timestamp, exclusive, in the account timezone' },
    relative_range: { type: 'string', enum: %w[this_month last_month last_7_days yesterday_today] },
    date_field: { type: 'string', enum: %w[created_at last_activity_at] },
    custom_attribute: {
      type: 'object', additionalProperties: false,
      properties: {
        key: { type: 'string' }, operator: { type: 'string', enum: %w[eq neq gt gte lt lte between contains is_null] },
        value: { type: %w[string number boolean] }, values: { type: 'array', minItems: 2, maxItems: 2, items: { type: %w[string number] } }
      }, required: %w[key]
    }
  }.freeze
  CONVERSATION_FILTERS = DATE_FILTERS.merge(
    status: { type: 'string', enum: Conversation.statuses.keys },
    priority: { type: %w[string null], enum: Conversation.priorities.keys + [nil] },
    inbox_id: { type: 'integer', minimum: 1 }, assignee_id: { type: %w[integer null], minimum: 1 },
    team_id: { type: %w[integer null], minimum: 1 }, labels: { type: 'array', items: { type: 'string' } }
  ).freeze
  CONTACT_FILTERS = DATE_FILTERS.merge(
    search: { type: 'string', minLength: 2 }, labels: { type: 'array', items: { type: 'string' } },
    country_code: { type: 'string' }, blocked: { type: 'boolean' }
  ).freeze

  def self.filter_schema
    properties = self::FILTERS
    { type: 'object', additionalProperties: false, properties: properties }.deep_stringify_keys
  end

  def self.group_options
    PERIODS.keys + self::GROUPS
  end

  def self.help
    filters = filter_schema['properties'].map do |name, property|
      allowed = property['enum'] || property.dig('items', 'enum')
      detail = allowed ? "allowed values #{allowed.join(', ')}" : property['description']
      detail ? "#{name}: #{detail}" : name
    end.join('; ')
    "- #{self::NAME}: filters #{filters}. Group by: #{group_options.join(', ')}"
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def matching(filters, as_of:)
    unless filters.is_a?(Hash) && JSONSchemer.schema(self.class.filter_schema).valid?(filters.deep_stringify_keys)
      raise ArgumentError, "Invalid #{self.class::NAME} filters; allowed fields: #{self.class.filter_schema['properties'].keys.join(', ')}"
    end

    filters = filters.deep_stringify_keys
    field = filters['date_field'] || self.class::DATE_FIELDS.first
    relative_range = filters.key?('relative_range')
    filters = resolve_relative_range(filters, as_of)
    relation = filter(scope, filters)
    apply_dates(relation, filters, as_of, field, allow_future_before: relative_range).reorder(nil)
  end

  def group_counts(relation, group, date_field: self.class::DATE_FIELDS.first)
    raise ArgumentError, "group_by must be one of: #{self.class.group_options.join(', ')}" unless self.class.group_options.include?(group)

    counts = if PERIODS.key?(group)
               relation.where.not(date_field => nil).group_by_period(group, date_field, time_zone: timezone.name,
                                                                                        week_start: :monday).count
                       .transform_keys { |date| date.strftime(PERIODS.fetch(group)) }
             else
               counts_by(relation, group)
             end
    raise ArgumentError, "group_by #{group} produces more than #{MAX_GROUPS} groups; narrow the filters" if counts.size > MAX_GROUPS

    counts.sort_by { |_, count| -count }.map { |value, count| { group: value.to_s, count: count } }
  end

  def aggregate_value(relation, aggregate)
    aggregate_value_for(relation, aggregate)
  end

  private

  def timezone
    ActiveSupport::TimeZone[@account.reporting_timezone.presence || Time.zone.name] || Time.zone
  end

  def apply_dates(relation, filters, as_of, field, allow_future_before: false)
    return relation unless filters['since'] || filters['before']

    since, before = date_range(filters, as_of, allow_future_before: allow_future_before)
    range = relation.where(relation.klass.arel_table[field].gteq(since)) if since
    (range || relation).where(relation.klass.arel_table[field].lt(before))
  end

  def date_range(filters, as_of, allow_future_before:)
    since = parse_date(filters['since']) if filters['since']
    before = parse_date(filters['before']) if filters['before']
    before ||= as_of
    validate_date_range(since, before, as_of, allow_future_before: allow_future_before)

    [since, before]
  end

  def validate_date_range(since, before, as_of, allow_future_before:)
    validate_date_order(since, before)
    validate_date_limit(since, before)
    validate_before_not_future(before, as_of, allow_future_before: allow_future_before)
  end

  def validate_date_order(since, before)
    raise ArgumentError, 'since is required when before is provided' if before && since.nil?
    raise ArgumentError, 'since must be earlier than before' if since && since >= before
  end

  def validate_date_limit(since, before)
    raise ArgumentError, "date range cannot exceed #{MAX_RANGE.to_i / 1.day.to_i} days" if since && before - since > MAX_RANGE
  end

  def validate_before_not_future(before, as_of, allow_future_before:)
    return if allow_future_before

    raise ArgumentError, 'before cannot be in the future' if before > as_of
  end

  def parse_date(value)
    return timezone.parse(value).beginning_of_day if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Time.iso8601(value).in_time_zone(timezone)
  rescue ArgumentError, TypeError
    raise ArgumentError, 'dates must be ISO 8601 dates or timestamps'
  end

  def custom_attribute_filter(relation, filters, model)
    attribute = filters['custom_attribute']
    return relation unless attribute

    query = Captain::Copilot::Resources::CustomAttributeQuery.new(account: @account, user: @user, model: model)
    query.filter(relation, attribute)
  end

  def aggregate_value_for(relation, aggregate)
    return { function: 'count', value: relation.count } if aggregate.nil?

    query = Captain::Copilot::Resources::CustomAttributeQuery.new(
      account: @account, user: @user, model: self.class::ATTRIBUTE_MODEL
    )
    query.aggregate(relation, function: aggregate['function'], key: aggregate['key'])
  end

  def resolve_relative_range(filters, as_of)
    period = filters['relative_range']
    return filters unless period
    raise ArgumentError, 'relative_range cannot be combined with since or before' if filters['since'] || filters['before']

    builder = RELATIVE_RANGE_BUILDERS[period]
    raise ArgumentError, "Unknown relative_range #{period}" unless builder

    since, before = builder.call(as_of.in_time_zone(timezone))
    filters.except('relative_range').merge('since' => since.iso8601, 'before' => before.iso8601)
  end

  def column_counts(relation, column, names: nil)
    counts = relation.group(column).count
    named = names ? names.where(id: counts.keys.compact).to_h { |record| [record.id, "#{record.name} (ID #{record.id})"] } : {}
    counts.transform_keys { |key| key.nil? ? 'None' : named.fetch(key) { key.to_s } }
  end

  def label_counts(relation)
    taggings = ActsAsTaggableOn::Tagging.where(taggable_type: relation.klass.name, context: 'labels')
    counts = taggings.where(taggable_id: relation.reselect(:id)).joins(:tag).group('tags.name').count
    unlabeled = relation.where.not(id: taggings.select(:taggable_id)).count
    unlabeled.positive? ? counts.merge('No label' => unlabeled) : counts
  end
end
