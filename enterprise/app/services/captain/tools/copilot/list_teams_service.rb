class Captain::Tools::Copilot::ListTeamsService < Captain::Tools::BaseTool
  def self.name
    'list_teams'
  end

  description 'List up to 100 teams in this account so they can be assigned by integer team_id'

  def execute
    @assistant.account.teams.order(:name).limit(100).map { |team| { id: team.id, name: team.name } }
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
