class Captain::Tools::Copilot::ListCustomAttributesService < Captain::Tools::BaseTool
  def self.name
    'list_custom_attributes'
  end

  description 'List up to 100 custom attribute definitions available for conversations or contacts in this account'
  parameter :resource, type: :string, description: 'Resource kind: conversations or contacts', required: true

  def execute(resource:)
    model = model_for(resource)
    authorize_resource!(model)
    @assistant.account.custom_attribute_definitions.where(attribute_model: model).order(:attribute_display_name).limit(100).map do |definition|
      { key: definition.attribute_key, name: definition.attribute_display_name, type: definition.attribute_display_type }
    end
  rescue ArgumentError => e
    { error: e.message }
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage') || user_has_permission('contact_manage')
  end

  def conversation_permission?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage')
  end

  def model_for(resource)
    { 'conversations' => 'conversation_attribute', 'contacts' => 'contact_attribute' }.fetch(resource) do
      raise ArgumentError, 'resource must be conversations or contacts'
    end
  end

  def authorize_resource!(model)
    return if model == 'contact_attribute' && user_has_permission('contact_manage')
    return if model == 'conversation_attribute' && conversation_permission?

    resource_name = model.delete_suffix('_attribute')
    raise ArgumentError, "You do not have permission to view #{resource_name}"
  end
end
