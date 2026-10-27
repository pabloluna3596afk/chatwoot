class Captain::Tools::Copilot::ListLabelsService < Captain::Tools::BaseTool
  def self.name
    'list_labels'
  end

  description 'List up to 100 label names and IDs in this account so they can be used in get_data filters'

  def execute
    @assistant.account.labels.order(:title).limit(100).map { |label| { id: label.id, name: label.title } }
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage') || user_has_permission('contact_manage')
  end
end
