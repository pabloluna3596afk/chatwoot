class Captain::Copilot::Resources::CustomAttributeQuery
  FILTER_OPERATORS = {
    'text' => %w[eq neq contains is_null], 'number' => %w[eq neq gt gte lt lte between is_null],
    'currency' => %w[eq neq gt gte lt lte between is_null], 'percent' => %w[eq neq gt gte lt lte between is_null],
    'date' => %w[eq neq gt gte lt lte between is_null], 'datetime' => %w[eq neq gt gte lt lte between is_null],
    'list' => %w[eq neq is_null], 'multi_list' => %w[eq neq contains is_null], 'checkbox' => %w[eq neq is_null]
  }.freeze
  NUMERIC_TYPES = %w[number currency percent].freeze
  COMPARISON_OPERATORS = { 'eq' => '=', 'neq' => '!=', 'gt' => '>', 'gte' => '>=', 'lt' => '<', 'lte' => '<=' }.freeze

  def initialize(account:, user:, model:)
    @account = account
    @user = user
    @model = model
  end

  def filter(relation, attribute)
    definition = find_definition(attribute['key'])
    operator = attribute.fetch('operator', 'eq')
    validate_operator!(definition, operator)
    validate_values!(definition, attribute, operator)
    return filter_contacts(relation, definition, attribute) if @model == 'contact_attribute' && operator == 'eq'

    apply_filter(relation, definition, attribute, operator)
  end

  def aggregate(relation, function:, key: nil)
    return { function: 'count', value: relation.count } if function == 'count'
    raise ArgumentError, 'aggregate function must be count, sum, avg, min, or max' unless %w[sum avg min max].include?(function)

    definition = find_definition(key)
    unless NUMERIC_TYPES.include?(definition.attribute_display_type)
      raise ArgumentError, "#{function} requires a numeric custom attribute; #{key} is #{definition.attribute_display_type}"
    end

    column = custom_attribute_column(relation, definition)
    numeric_value = "CASE WHEN #{column} ~ '^(-|)[0-9]+([.][0-9]+|)$' THEN (#{column})::numeric END"
    value = relation.pick(Arel.sql("#{function.upcase}(#{numeric_value})"))
    { function: function, key: definition.attribute_key, value: value }
  end

  private

  def find_definition(key)
    definition = @account.custom_attribute_definitions.find_by(attribute_model: @model, attribute_key: key)
    return definition if definition

    resource = @model.delete_suffix('_attribute')
    raise ArgumentError, "Unknown #{resource} custom attribute key: #{key}"
  end

  def validate_operator!(definition, operator)
    return if FILTER_OPERATORS.fetch(definition.attribute_display_type).include?(operator)

    raise ArgumentError, "Operator #{operator} is not supported for #{definition.attribute_display_type} custom attributes"
  end

  def validate_values!(definition, attribute, operator)
    if operator == 'is_null'
      raise ArgumentError, 'is_null does not accept a value' if attribute.key?('value') || attribute.key?('values')

      return
    end
    validate_value_shape!(attribute, operator)
    values = operator == 'between' ? attribute['values'] : [attribute['value']]
    validate_value_types!(values, definition.attribute_display_type, operator)
    validate_value_order!(values, operator)
    validate_date_values!(values, definition.attribute_display_type)
    validate_options!(values, definition)
  end

  def validate_value_shape!(attribute, operator)
    return validate_between_shape!(attribute) if operator == 'between'

    raise ArgumentError, 'only between accepts values' if attribute.key?('values')
    raise ArgumentError, "Operator #{operator} requires a value" if attribute['value'].nil?
  end

  def validate_between_shape!(attribute)
    raise ArgumentError, 'between accepts values, not value' if attribute.key?('value')
    raise ArgumentError, 'between requires exactly two values' unless attribute['values']&.length == 2
    raise ArgumentError, 'Operator between requires two values' if attribute['values'].any?(&:nil?)
  end

  def validate_value_types!(values, type, operator)
    expected = case type
               when *NUMERIC_TYPES then :number
               when 'checkbox' then :boolean
               else :string
               end
    valid = values.all? { |value| value_matches_type?(value, expected) }
    raise ArgumentError, "#{type} custom attribute values must be #{expected}" unless valid
    return unless operator == 'between' && values.length != 2

    raise ArgumentError, 'between requires exactly two values'
  end

  def value_matches_type?(value, type)
    case type
    when :number then value.is_a?(Numeric) && value.finite?
    when :boolean then value == true || value == false
    when :string then value.is_a?(String)
    end
  end

  def validate_value_order!(values, operator)
    return unless operator == 'between'
    raise ArgumentError, 'between values must be in ascending order' if values[0] > values[1]
  end

  def validate_date_values!(values, type)
    return unless %w[date datetime].include?(type)

    values.each { |value| type == 'date' ? Date.iso8601(value) : Time.iso8601(value) }
  rescue ArgumentError, TypeError
    raise ArgumentError, "#{type} custom attribute values must be ISO 8601"
  end

  def validate_options!(values, definition)
    return unless %w[list multi_list].include?(definition.attribute_display_type)

    options = Array(definition.attribute_values)
    return if options.empty? || values.all? { |value| options.include?(value) }

    raise ArgumentError, "Value is not an option for #{definition.attribute_display_type} custom attribute"
  end

  def filter_contacts(relation, definition, attribute)
    payload = ActionController::Parameters.new(
      payload: [{ attribute_key: definition.attribute_key, custom_attribute_type: @model, filter_operator: 'equal_to',
                  values: [attribute['value']], query_operator: '' }]
    )
    matching = Contacts::FilterService.new(@account, @user, payload).perform[:contacts]
    relation.where(id: matching.reselect(:id))
  end

  def apply_filter(relation, definition, attribute, operator)
    return null_filter(relation, definition) if operator == 'is_null'
    return multi_list_filter(relation, definition, attribute['value'], operator) if definition.attribute_display_type == 'multi_list'

    apply_comparison(relation, definition, attribute, operator)
  end

  def null_filter(relation, definition)
    relation.where("#{custom_attribute_column(relation, definition)} IS NULL")
  end

  def multi_list_filter(relation, definition, value, operator)
    containment = "#{relation.klass.table_name}.custom_attributes @> ?::jsonb"
    payload = { definition.attribute_key => [value] }.to_json
    return relation.where("NOT (#{containment})", payload) if operator == 'neq'

    relation.where(containment, payload)
  end

  def apply_comparison(relation, definition, attribute, operator)
    column = custom_attribute_column(relation, definition)
    value = attribute['value']
    value = value.to_s if definition.attribute_display_type == 'checkbox'
    sql_value = comparable_column(column, definition.attribute_display_type)
    comparison(relation, sql_value, attribute, operator, value)
  end

  def comparison(relation, sql_value, attribute, operator, value)
    return relation.where("#{sql_value} BETWEEN ? AND ?", *attribute['values']) if operator == 'between'
    return relation.where("#{sql_value} ILIKE ?", "%#{Contact.sanitize_sql_like(value)}%") if operator == 'contains'

    relation.where("#{sql_value} #{COMPARISON_OPERATORS.fetch(operator)} ?", value)
  end

  def custom_attribute_column(relation, definition)
    key = ActiveRecord::Base.connection.quote(definition.attribute_key)
    "#{relation.klass.table_name}.custom_attributes ->> #{key}"
  end

  def comparable_column(column, type)
    case type
    when *NUMERIC_TYPES then "CASE WHEN #{column} ~ '^(-|)[0-9]+([.][0-9]+|)$' THEN (#{column})::numeric END"
    when 'date' then "CASE WHEN #{column} ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN (#{column})::date END"
    when 'datetime' then "(#{column})::timestamptz"
    else column
    end
  end
end
