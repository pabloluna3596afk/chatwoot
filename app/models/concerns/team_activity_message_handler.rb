module TeamActivityMessageHandler
  extend ActiveSupport::Concern

  private

  def create_team_change_activity(user_name)
    names = activity_actor_names(user_name)
    user_name = activity_message_owner(user_name)
    return unless user_name

    key = generate_team_change_activity_key
    params = { assignee_name: assignee&.name, team_name: team&.name, user_name: user_name }
    params[:team_name] = generate_team_name_for_activity if key == 'removed'
    content = I18n.t("conversations.activity.team.#{key}", **params)
    names << params[:team_name]
    names << params[:assignee_name] if key == 'assigned_with_assignee'

    enqueue_activity_message(activity_message_params(content, names: names)) if content
  end

  def generate_team_change_activity_key
    team = Team.find_by(id: team_id)
    key = team.present? ? 'assigned' : 'removed'
    key += '_with_assignee' if key == 'assigned' && saved_change_to_assignee_id? && assignee
    key
  end

  def generate_team_name_for_activity
    previous_team_id = previous_changes[:team_id][0]
    Team.find_by(id: previous_team_id)&.name if previous_team_id.present?
  end
end
