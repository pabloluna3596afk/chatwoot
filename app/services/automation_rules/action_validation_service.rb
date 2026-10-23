class AutomationRules::ActionValidationService
  PARAMETERLESS_ACTIONS = %w[remove_assigned_agent remove_assigned_team mute_conversation resolve_conversation
                             open_conversation pending_conversation notify_assignee assign_team].freeze
  REQUIRED_FIELDS = {
    'send_email_to_team' => %w[team_ids message],
    'send_whatsapp_template' => %w[inbox_id name language],
    'update_contact_custom_attribute' => %w[attribute_key],
    'update_conversation_custom_attribute' => %w[attribute_key]
  }.freeze

  def initialize(rule)
    @rule = rule
  end

  def perform
    @rule.actions.each_with_index.filter_map do |action, index|
      message = action_error(action)
      { action_index: index, message: message } if message
    end
  end

  private

  def action_error(action)
    name = action['action_name']
    return 'The action is not supported.' unless @rule.actions_attributes.include?(name)
    return if PARAMETERLESS_ACTIONS.include?(name)

    parameters_error(name, action['action_params'])
  end

  def parameters_error(name, params)
    special = special_parameters_error(name, params)
    return special unless special == :none
    return structured_parameters_error(name, params) if REQUIRED_FIELDS.key?(name)
    return if params.is_a?(Array) && params.any? && params.all?(&:present?)

    'Required action parameters must not be empty.'
  end

  # Actions with their own parameter contract. :none means the action has no special rule.
  def special_parameters_error(name, params)
    case name
    when 'create_internal_task' then AutomationRules::InternalTaskParameters.new(params, account: @rule.account).error
    when 'snooze_conversation' then Conversations::SnoozeParameters.new(params).error
    when 'send_message' then message_parameters_error(params)
    else :none
    end
  end

  def message_parameters_error(params)
    content = params.is_a?(Array) ? params.first : params
    return if content.is_a?(String) && content.present?

    'Message content must not be empty.'
  end

  def structured_parameters_error(name, params)
    data = params.is_a?(Array) ? params.first : params
    fields = REQUIRED_FIELDS.fetch(name)
    return 'Required action parameters must not be empty.' unless data.is_a?(Hash)
    return 'Team email parameters must be an array.' if name == 'send_email_to_team' && !params.is_a?(Array)

    missing = fields.select { |key| data[key].blank? }
    "Required action parameters must not be empty: #{missing.join(', ')}." if missing.any?
  end
end
