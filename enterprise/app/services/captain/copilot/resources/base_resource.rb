class Captain::Copilot::Resources::BaseResource
  include Captain::Copilot::ConversationAccess

  PERIODS = { 'day' => '%Y-%m-%d', 'week' => 'week of %Y-%m-%d', 'month' => '%Y-%m', 'year' => '%Y' }.freeze
  MAX_GROUPS = 100
  MAX_RANGE = 366.days

  DATE_FILTERS = {
    since: { type: 'string', description: 'ISO 8601 date or timestamp, inclusive, in the account timezone' },
    before: { type: 'string', description: 'ISO 8601 date or timestamp, exclusive, in the account timezone' },
    date_field: { type: 'string', enum: %w[created_at last_activity_at] },
    custom_attribute: {
      type: 'object', additionalProperties: false,
      properties: { key: { type: 'string' }, value: { type: %w[string number boolean] } },
      required: %w[key value]
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
    relation = filter(scope, filters)
    apply_dates(relation, filters, as_of, field).reorder(nil)
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

  private

  def timezone
    ActiveSupport::TimeZone[@account.reporting_timezone.presence || Time.zone.name] || Time.zone
  end

  def apply_dates(relation, filters, as_of, field)
    return relation unless filters['since'] || filters['before']

    since, before = date_range(filters, as_of)
    range = relation.where(relation.klass.arel_table[field].gteq(since)) if since
    (range || relation).where(relation.klass.arel_table[field].lt(before))
  end

  def date_range(filters, as_of)
    since = parse_date(filters['since']) if filters['since']
    before = parse_date(filters['before']) if filters['before']
    before ||= as_of
    validate_date_range(since, before, as_of)

    [since, before]
  end

  def validate_date_range(since, before, as_of)
    validate_date_order(since, before)
    validate_date_limit(since, before)
    validate_before_not_future(before, as_of)
  end

  def validate_date_order(since, before)
    raise ArgumentError, 'since is required when before is provided' if before && since.nil?
    raise ArgumentError, 'since must be earlier than before' if since && since >= before
  end

  def validate_date_limit(since, before)
    raise ArgumentError, "date range cannot exceed #{MAX_RANGE.to_i / 1.day.to_i} days" if since && before - since > MAX_RANGE
  end

  def validate_before_not_future(before, as_of)
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

    definition = @account.custom_attribute_definitions.find_by(attribute_model: model, attribute_key: attribute['key'])
    raise ArgumentError, "Unknown #{model.delete_suffix('_attribute')} custom attribute key: #{attribute['key']}" unless definition

    if model == 'contact_attribute'
      payload = ActionController::Parameters.new(
        payload: [{ attribute_key: attribute['key'], custom_attribute_type: model, filter_operator: 'equal_to',
                    values: [attribute['value']], query_operator: '' }]
      )
      matching_contacts = Contacts::FilterService.new(@account, @user, payload).perform[:contacts]
      return relation.where(id: matching_contacts.reselect(:id))
    end

    relation.where("#{relation.klass.table_name}.custom_attributes ->> ? = ?", definition.attribute_key, attribute['value'].to_s)
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
