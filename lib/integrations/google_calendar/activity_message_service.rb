class Integrations::GoogleCalendar::ActivityMessageService
  USER_ACTIONS = %w[event_created event_updated event_deleted].freeze

  def initialize(conversation:, action_type:, user:, event_data: {})
    @conversation = conversation
    @action_type = action_type
    @user = user
    @event_data = event_data
  end

  def perform
    return unless conversation && user

    content = generate_activity_content
    return if content.blank?

    Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params(content))
  end

  private

  attr_reader :conversation, :action_type, :user, :event_data

  def generate_activity_content
    I18n.t(
      "conversations.activity.calendar.#{action_type}",
      user_name: user.name,
      event_title: event_data[:summary],
      inbox_name: conversation.inbox&.name
    )
  rescue I18n::MissingTranslationData
    nil
  end

  def activity_message_params(content)
    names = [event_data[:summary]]
    names << user.name if USER_ACTIONS.include?(action_type.to_s)
    names << conversation.inbox&.name if action_type.to_s == 'event_created'
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content,
      content_attributes: ActivityMessageNames.attributes(content, names).merge(template_settings)
    }
  end

  def template_settings
    return {} unless %w[notice_not_sent cancellation_notice_not_sent].include?(action_type.to_s)

    { 'calendar_template_settings' => { 'reason' => 'template_unavailable',
                                      'path' => "/app/accounts/#{conversation.account_id}/settings/templates" } }
  end
end
