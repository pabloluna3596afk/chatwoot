module AssigneeActivityMessageHandler
  extend ActiveSupport::Concern

  private

  def create_assignee_change_activity(user_name)
    user_name = activity_message_owner(user_name)

    return unless user_name

    content = generate_assignee_change_activity_content(user_name)
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end

  # A conversation given to Captain or to a bot (no person is assigned, so there is no assignee change to report).
  # When Captain takes a pending conversation the status activity already says it.
  def create_ai_assignee_change_activity(user_name)
    return if ai_assignee.blank? || (saved_change_to_status? && captain_attended?)

    content = I18n.t('conversations.activity.ai_assignee.assigned', assistant: ai_assignee.name, actor: activity_actor_name(user_name))
    ::Conversations::ActivityMessageJob.perform_later(
      self,
      activity_message_params(content, content_attributes: { activity: { type: 'ai_assignee_changed', source: activity_source(user_name) } })
    )
  end

  def generate_assignee_change_activity_content(user_name)
    params = { assignee_name: assignee&.name || '', user_name: user_name }
    key = assignee_id ? 'assigned' : 'removed'
    key = 'self_assigned' if self_assign? assignee_id
    I18n.t("conversations.activity.assignee.#{key}", **params)
  end

  def activity_message_owner(user_name)
    AutomationRuleActor.activity_owner(user_name)
  end
end
