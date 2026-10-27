class Captain::Tools::Copilot::DescribeSchemaService < Captain::Tools::BaseTool
  def self.name
    'describe_schema'
  end

  description 'Describe fields, custom attribute types and allowed analytical operations for a CRM resource'
  parameter :resource, type: :string, description: 'Resource kind: conversations or contacts', required: true

  STANDARD_FIELDS = {
    'conversations' => %w[status priority assignee_id inbox_id team_id display_id campaign_id labels created_at last_activity_at],
    'contacts' => %w[name email phone_number identifier country_code city company_name created_at last_activity_at blocked]
  }.freeze

  def execute(resource:)
    model, permission = resource_access(resource)
    authorize_resource!(permission)
    resource_class = Captain::Copilot::Resources.build(resource, account: @assistant.account, user: @user).class
    definitions = @assistant.account.custom_attribute_definitions.where(attribute_model: model).order(:attribute_display_name).limit(100)

    {
      resource: resource,
      standard_fields: STANDARD_FIELDS.fetch(resource).map do |key|
        { key: key, type: standard_type(key), filterable: resource_class.filter_schema['properties'].key?(key) }
      end,
      custom_attributes: definitions.map do |definition|
        attribute_schema(definition)
      end,
      group_by: resource_class.group_options,
      aggregate_functions: %w[count sum avg min max],
      relative_ranges: %w[this_month last_month last_7_days yesterday_today]
    }
  rescue ArgumentError => e
    { error: e.message }
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage') || user_has_permission('contact_manage')
  end

  private

  def resource_access(resource)
    case resource
    when 'conversations' then %w[conversation_attribute conversation]
    when 'contacts' then %w[contact_attribute contact]
    else raise ArgumentError, 'resource must be conversations or contacts'
    end
  end

  def authorize_resource!(permission)
    allowed = if permission == 'contact'
                user_has_permission('contact_manage')
              else
                %w[conversation_manage conversation_unassigned_manage conversation_participating_manage].any? do |name|
                  user_has_permission(name)
                end
              end
    raise ArgumentError, "You do not have permission to view #{permission}s" unless allowed
  end

  def attribute_schema(definition)
    type = definition.attribute_display_type
    numeric = %w[number currency percent].include?(type)
    temporal = %w[date datetime].include?(type)
    string = %w[text multi_list].include?(type)
    operators = %w[eq neq is_null]
    operators = %w[eq neq gt gte lt lte between is_null] if numeric || temporal
    operators = %w[eq neq contains is_null] if string
    { key: definition.attribute_key, name: definition.attribute_display_name, type: type,
      values: (%w[list multi_list].include?(type) ? definition.attribute_values : nil),
      filter_operators: operators, aggregate_functions: (numeric ? %w[sum avg min max] : []) }.compact
  end

  def standard_type(key)
    return 'datetime' if %w[created_at last_activity_at].include?(key)
    return 'boolean' if key == 'blocked'
    return 'integer' if %w[assignee_id inbox_id team_id display_id campaign_id].include?(key)
    return 'list' if %w[status priority labels].include?(key)

    'text'
  end
end
