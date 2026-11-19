class Captain::HandoffRouter
  Routing = Struct.new(:kind, :assignee, :team, :priority, :conversation, keyword_init: true) do
    def note
      lines = [assignment_note]
      lines << translate('priority_high') if priority && conversation.high?
      lines.compact.presence&.join("\n")
    end

    def append_to(message)
      line = note
      message.update!(content: [message.content, line].join("\n")) if line && message
    end

    private

    def assignment_note
      if team
        key = conversation.assignee ? 'team_assigned' : 'team_unassigned'
        translate(key, team: team.name, agent: conversation.assignee&.name)
      elsif assignee
        translate('previous_agent', agent: assignee.name)
      end
    end

    def translate(key, **values)
      I18n.t("captain.notes.handoff_routing.#{key}", **values, locale: conversation.account.locale)
    end
  end

  def self.eligible_teams(assistant, inbox_ids: assistant.inboxes.select(:id))
    member_ids = InboxMember.where(inbox_id: inbox_ids).select(:user_id)
    assistant.account.teams.where(allow_auto_assign: true)
             .where(id: TeamMember.where(user_id: member_ids).select(:team_id)).order(:id)
  end

  def initialize(conversation:, assistant:, team_name: nil, urgent: nil)
    @conversation = conversation
    @assistant = assistant
    @team_name = team_name
    @urgent = urgent
  end

  def plan
    kind = @conversation.additional_attributes['captain_reopened_at'].present? ? :reopened : :new
    settings = @assistant.handoff_routing.fetch(kind.to_s)
    routing = Routing.new(kind: kind, conversation: @conversation, priority: handoff_priority)
    case settings['mode']
    when 'last_agent' then routing.assignee = previous_agent(kind)
    when 'team', 'ai_team' then routing.team = selected_team(settings)
    end
    routing
  end

  private

  def handoff_priority
    policy = @assistant.handoff_priority
    :high if policy == 'always' || (policy == 'on_signal' && @urgent == true)
  end

  def previous_agent(kind)
    id = if kind == :reopened
           @conversation.additional_attributes['captain_previous_assignee_id']
         else
           @conversation.contact.conversations.where(inbox_id: @conversation.inbox_id).where.not(id: @conversation.id)
                        .where.not(assignee_id: nil).order(last_activity_at: :desc, id: :desc).pick(:assignee_id)
         end
    return unless @conversation.inbox.member_ids_with_assignment_capacity.include?(id)
    return unless OnlineStatusTracker.get_available_users(@conversation.account_id)[id.to_s] == 'online'

    @conversation.inbox.members.find_by(id: id)
  end

  def selected_team(settings)
    teams = self.class.eligible_teams(@assistant, inbox_ids: [@conversation.inbox_id])
    team = settings['mode'] == 'team' ? teams.find_by(id: settings['team_id']) : teams.find_by(name: @team_name)
    return team if team

    event = settings['mode'] == 'team' ? 'team_unavailable' : 'team_rejected'
    Rails.logger.info("handoff_routing #{event} conversation_id=#{@conversation.id} team_name=#{@team_name.inspect}")
    nil
  end
end
