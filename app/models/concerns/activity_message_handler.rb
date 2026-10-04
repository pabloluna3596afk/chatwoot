module ActivityMessageHandler
  extend ActiveSupport::Concern

  include AssigneeActivityMessageHandler
  include PriorityActivityMessageHandler
  include LabelActivityMessageHandler
  include SlaActivityMessageHandler
  include TeamActivityMessageHandler

  private

  def create_activity
    with_account_locale do
      user_name = determine_user_name

      handle_status_change(user_name)
      handle_priority_change(user_name)
      handle_label_change(user_name)
      handle_sla_policy_change(user_name)
    end
  end

  # The activity text is written once, when the event happens, and everyone reads it afterwards: it is worded in the
  # language of the account. Jobs and webhooks run in the default locale (English), not in the account's.
  def with_account_locale(&)
    code = account&.locale.to_s
    available = I18n.available_locales.map(&:to_s)
    locale = [code, code.split('_').first].find { |candidate| available.include?(candidate) }

    locale ? I18n.with_locale(locale, &) : yield
  end

  def determine_user_name
    # AgentBot status changes (pending→open for bot reply) must not attribute
    # "reabierta por …" to a human/admin API token or to the bot display name.
    return if Current.user.is_a?(AgentBot)

    Current.user&.name
  end

  def handle_status_change(user_name)
    return unless saved_change_to_status?

    status_change_activity(user_name)
  end

  def handle_priority_change(user_name)
    return unless saved_change_to_priority?

    priority_change_activity(user_name)
  end

  def handle_label_change(user_name)
    return unless saved_change_to_label_list?

    create_label_change(activity_message_owner(user_name))
  end

  def handle_sla_policy_change(user_name)
    return unless saved_change_to_sla_policy_id?

    sla_change_type = determine_sla_change_type
    create_sla_change_activity(sla_change_type, activity_message_owner(user_name))
  end

  def status_change_activity(user_name)
    captain_content = captain_status_change_activity_content(user_name)
    content = captain_content || standard_status_change_activity_content(user_name)

    return if content.blank?

    activity = { type: 'conversation_status_changed', status: status }
    activity[:source] = captain_activity_source(user_name) if captain_content.present?
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content, content_attributes: { activity: activity }))
  end

  # Captain taking a conversation, or letting it go to the team, says so in plain words instead of "marked as pending",
  # and says who gave it to Captain.
  def captain_status_change_activity_content(user_name)
    if captain_attended?
      I18n.t('conversations.activity.status.captain_attending', assistant: ai_assignee.name, actor: activity_actor_name(user_name))
    elsif open? && saved_change_to_captain_handed_off_at? && captain_handed_off_at.present?
      I18n.t('conversations.activity.status.captain_handed_off', assistant: captain_assistant_name)
    end
  end

  def captain_assistant_name
    inbox.try(:captain_assistant)&.name || 'Captain'
  end

  # Where a Captain activity comes from: the assistant itself when it hands the conversation over, else whoever
  # (or whatever) assigned it.
  def captain_activity_source(user_name)
    return { type: 'captain', name: captain_assistant_name } if open? && captain_handed_off_at.present?

    activity_source(user_name)
  end

  # Who made a change: a person, an automation rule, an assignment policy (or the inbox's default one) or the system.
  # The activity keeps it as content_attributes.activity.source so the dashboard can show it.
  def activity_source(user_name)
    return { type: 'user', name: user_name } if user_name.present?

    case Current.executed_by
    when AutomationRule then { type: 'automation_rule', name: Current.executed_by.name }
    when AssignmentPolicy then { type: 'assignment_policy', name: Current.executed_by.name }
    when Inbox then { type: 'assignment_policy', name: I18n.t('auto_assignment.default_policy_name') }
    else { type: 'system' }
    end
  end

  # The same, worded for a sentence ("Pablo", "la automatización «X»", "la política de asignación «Y»", "el sistema").
  def activity_actor_name(user_name)
    AutomationRuleActor.activity_owner(user_name) || I18n.t('automation.system_name')
  end

  def standard_status_change_activity_content(user_name)
    return automation_status_change_activity_content if Current.executed_by.present?

    user_status_change_activity_content(user_name)
  end

  def auto_resolve_message_key(minutes)
    if minutes >= 1440 && (minutes % 1440).zero?
      { key: 'auto_resolved_days', count: minutes / 1440 }
    elsif minutes >= 60 && (minutes % 60).zero?
      { key: 'auto_resolved_hours', count: minutes / 60 }
    else
      { key: 'auto_resolved_minutes', count: minutes }
    end
  end

  def user_status_change_activity_content(user_name)
    if user_name
      I18n.t("conversations.activity.status.#{status}", user_name: user_name, status_label: status_label_word)
    elsif Current.contact.present? && resolved?
      I18n.t('conversations.activity.status.contact_resolved', contact_name: Current.contact.name.capitalize, status_label: status_label_word)
    elsif resolved?
      message_data = auto_resolve_message_key(auto_resolve_after || 0)
      I18n.t("conversations.activity.status.#{message_data[:key]}", count: message_data[:count], status_label: status_label_word)
    end
  end

  def automation_status_change_activity_content
    if Current.executed_by.instance_of?(AutomationRule)
      I18n.t("conversations.activity.status.#{status}",
             user_name: AutomationRuleActor.activity_owner(nil),
             status_label: status_label_word)
    elsif Current.executed_by.instance_of?(Contact)
      Current.executed_by = nil
      I18n.t('conversations.activity.status.system_auto_open')
    end
  end

  # Resolve the human-readable label for the current status. Defaults to the
  # status name (e.g. "resolved") when the account has no custom resolved
  # label configured. The i18n strings use %{status_label} so this is required.
  def status_label_word
    return account.resolved_status_label_word if resolved?

    I18n.t("conversations.activity.status_labels.#{status}", default: status.to_s)
  end

  def activity_message_params(content, content_attributes: nil)
    params = {
      account_id: account_id,
      inbox_id: inbox_id,
      message_type: :activity,
      content: content
    }
    attrs = content_attributes || {}
    attrs = attrs.merge(message_source_attributes_for_activity) if message_source_attributes_for_activity.present?
    params[:content_attributes] = attrs if attrs.present?
    params
  end

  def message_source_attributes_for_activity
    case Current.executed_by
    when AutomationRule
      MessageSourceAttributes.for_automation(Current.executed_by)
    when Macro
      MessageSourceAttributes.for_macro(Current.executed_by)
    end
  end

  def create_muted_message
    create_mute_change_activity('muted')
  end

  def create_unmuted_message
    create_mute_change_activity('unmuted')
  end

  def create_mute_change_activity(change_type)
    return unless Current.user

    content = with_account_locale { I18n.t("conversations.activity.#{change_type}", user_name: Current.user.name) }
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end
end

ActivityMessageHandler.prepend_mod_with('ActivityMessageHandler')
