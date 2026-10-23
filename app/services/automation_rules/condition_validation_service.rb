class AutomationRules::ConditionValidationService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

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

    return true if query_operator.nil?
    return true if query_operator.empty?

    %w[AND OR].include?(query_operator.upcase)
  end

  def condition_filter_error(condition)
    key = condition['attribute_key']

    filter = @conversation_filters[key] || @contact_filters[key] || @message_filters[key]

    if filter
      'The filter operator is not supported for this attribute.' unless operation_valid?(condition, filter)
    else
      'The attribute is unavailable in this account.' unless custom_attribute_present?(key, condition['custom_attribute_type'])
    end
  end

  def operation_valid?(condition, filter)
    filter_operator = condition['filter_operator']

    # attribute changed is a special case
    return true if filter_operator == 'attribute_changed'

    filter['filter_operators'].include?(filter_operator)
  end

  def custom_attribute_present?(attribute_key, attribute_model)
    attribute_model = attribute_model.presence || self.class::ATTRIBUTE_MODEL

    @account.custom_attribute_definitions.where(
      attribute_model: attribute_model
    ).find_by(attribute_key: attribute_key).present?
  end
end
