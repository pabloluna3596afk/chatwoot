class TeamNotifications::AutomationNotificationMailer < ApplicationMailer
  def conversation_creation(conversation, team, message, flow_run: nil)
    return unless smtp_config_set_or_development?

    @agents = team.team_members
    @conversation = conversation
    records = { conversation: conversation, flow_run: flow_run }
    drops = Variables::ContextFactory.new(account: conversation.account, records: records).build(surface: flow_run ? 'flow' : 'automation')
    @custom_message = Variables::DeliveryRenderer.new(drops: drops).render(message, path: 'custom_message')
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)

    send_an_email_to_team
  rescue Variables::DeliveryRenderer::Error => e
    Variables::Omission.create_note(conversation: conversation, surface: 'notification', error: e)
  end

  private

  def send_an_email_to_team
    subject = 'This email has been sent via automation rule actions.'
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @agent_emails = @agents.collect(&:user).pluck(:email)
    send_mail_with_liquid(to: @agent_emails, subject: subject) and return
  end

  def liquid_droppables
    super.merge!({
                   conversation: @conversation,
                   inbox: @conversation.inbox
                 })
  end

  def liquid_locals
    super.merge!({
                   custom_message: @custom_message
                 })
  end
end
