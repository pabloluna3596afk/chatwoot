class Captain::Tools::Copilot::ListAgentsService < Captain::Tools::BaseTool
  def self.name
    'list_agents'
  end

  description 'List up to 100 agents and administrators in this account so they can be assigned by integer assignee_id'

  def execute
    @assistant.account.users.order(:name).limit(100).map { |agent| { id: agent.id, name: agent.name } }
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
