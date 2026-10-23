class AutomationRules::ConditionValidationService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze
  EVENTS = %w[conversation_created conversation_updated conversation_opened conversation_resolved message_created time_triggered].freeze
  MESSAGE_ATTRIBUTES = %w[content message_type private_note].freeze
  EQUALITY_OPERATORS = %w[equal_to not_equal_to].freeze
  PRESENCE_OPERATORS = %w[is_present is_not_present].freeze
  TEXT_OPERATORS = %w[contains does_not_contain].freeze
  COMPARISON_OPERATORS = %w[is_greater_than is_less_than days_before].freeze
  CUSTOM_OPERATORS = {
    'text' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + TEXT_OPERATORS,
    'link' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + TEXT_OPERATORS,
    'list' => EQUALITY_OPERATORS + PRESENCE_OPERATORS,
    'checkbox' => EQUALITY_OPERATORS + PRESENCE_OPERATORS,
    'multi_list' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + TEXT_OPERATORS,
    'number' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + COMPARISON_OPERATORS,
    'currency' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + COMPARISON_OPERATORS,
    'percent' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + COMPARISON_OPERATORS,
    'date' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + COMPARISON_OPERATORS,
    'datetime' => EQUALITY_OPERATORS + PRESENCE_OPERATORS + COMPARISON_OPERATORS
  }.freeze

  attr_reader :diagnostics

  def initialize(rule)
    @rule = rule
    @account = rule.account

    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)

    @conversation_filters = @filters['conversations']
    @contact_filters = @filters['contacts']
    @message_filters = @filters['messages']
  end

  def perform
    @diagnostics = []
    @rule.conditions.each_with_index do |condition, index|
      message = condition_error(condition)
      next unless message

      @diagnostics << { condition_index: index, attribute_key: condition['attribute_key'],
                        filter_operator: condition['filter_operator'], message: message }
      return false
    end

    true
  end

  private

  def condition_error(condition)
    filter_error = condition_filter_error(condition)
    return filter_error if filter_error

    'The query operator must be AND or OR.' unless valid_query_operator?(condition)
  end

  def valid_query_operator?(condition)
    query_operator = condition['query_operator']

    return true if query_operator.nil? || query_operator == ''

    query_operator.is_a?(String) && %w[AND OR].include?(query_operator.upcase)
  end

  def condition_filter_error(condition)
    key = condition['attribute_key']

    filter = @conversation_filters[key] || @contact_filters[key] || @message_filters[key]
    return standard_condition_error(condition, filter) if filter

    definition = custom_attribute(key, condition['custom_attribute_type'])
    return 'The attribute is unavailable in this account.' unless definition

    operators = CUSTOM_OPERATORS.fetch(definition.attribute_display_type)
    'The filter operator is not supported for this attribute.' unless operators.include?(condition['filter_operator'])
  end

  def standard_condition_error(condition, filter)
    key = condition['attribute_key']
    return 'The attribute is not supported for this event.' unless attribute_supported?(key)

    return if condition['filter_operator'] == 'attribute_changed'
    return if filter['filter_operators'].include?(condition['filter_operator'])

    'The filter operator is not supported for this attribute.'
  end

  # Embedded business rules evaluate conditions with a rule-like object that has no event or attribute list.
  def attribute_supported?(key)
    return true unless @rule.respond_to?(:event_name) && @rule.respond_to?(:conditions_attributes)

    @rule.conditions_attributes.include?(key) && attribute_supported_for_event?(key)
  end

  def attribute_supported_for_event?(key)
    EVENTS.include?(@rule.event_name) && (@rule.event_name == 'message_created' || MESSAGE_ATTRIBUTES.exclude?(key))
  end

  def custom_attribute(attribute_key, attribute_model)
    attribute_model = attribute_model.presence || self.class::ATTRIBUTE_MODEL
    return unless %w[contact_attribute conversation_attribute].include?(attribute_model)

    @account.custom_attribute_definitions.find_by(attribute_key: attribute_key, attribute_model: attribute_model)
  end
end
