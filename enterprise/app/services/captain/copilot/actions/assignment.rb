class Captain::Copilot::Actions::Assignment < Captain::Copilot::Actions::Base
  def self.action_name = 'assignment'

  def self.schema
    { type: 'object', description: 'Assign an agent, a team, or both. Use the corresponding list tool to get integer ids.',
      examples: [{ assignee_id: 7 }, { team_id: 3 }], additionalProperties: false,
      properties: { assignee_id: { type: 'integer' }, team_id: { type: 'integer' } } }
  end

  def required_permission = 'conversation_manage'

  def validate
    raise ArgumentError, 'Assignment requires a conversation target' unless @target_type == 'Conversation'

    super
  end

  def validate_payload!
    validate_payload_keys!(%w[assignee_id team_id], 'Use list agents/teams tools to get the integer ids.')
    validate_assignment_ids!
    validate_assignment_targets!
  end

  def preview
    super.merge(
      assignee: @assignee && { id: @assignee.id, name: @assignee.name },
      team: @team && { id: @team.id, name: @team.name }
    )
  end

  def execute
    result = nil
    result = Conversations::AssignmentService.new(conversation: target, assignee_id: @assignee.id).perform if @assignee
    @team = Conversations::TeamAssignmentService.new(conversation: target, team_id: @team.id).perform if @team
    { code: 'assignment_updated', assignee_id: @assignee&.id, team_id: @team&.id, result: result&.class&.name }
  end

  private

  def validate_assignment_ids!
    user_id = @payload['assignee_id']
    team_id = @payload['team_id']

    validate_agent_id!(user_id)
    validate_team_id!(team_id)
    raise ArgumentError, 'Agent or team is required' if user_id.blank? && team_id.blank?

    @assignee = @account.users.find_by(id: user_id) if user_id.present?
    @team = @account.teams.find_by(id: team_id) if team_id.present?
  end

  def validate_agent_id!(user_id)
    return if user_id.blank? || user_id.is_a?(Integer)

    raise ArgumentError, 'assignee_id must be an integer'
  end

  def validate_team_id!(team_id)
    return if team_id.blank? || team_id.is_a?(Integer)

    raise ArgumentError, 'team_id must be an integer'
  end

  def validate_assignment_targets!
    raise ArgumentError, 'Agent does not exist in this account' if @payload['assignee_id'].present? && @assignee.blank?
    raise ArgumentError, 'Team does not exist in this account' if @payload['team_id'].present? && @team.blank?
  end
end
