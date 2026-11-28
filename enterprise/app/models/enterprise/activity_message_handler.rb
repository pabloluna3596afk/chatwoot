module Enterprise::ActivityMessageHandler
  def automation_status_change_activity_content
    return super unless Current.executed_by.instance_of?(Captain::Assistant)

    locale = Current.executed_by.account.locale
    key = captain_activity_key
    return unless key

    I18n.t(key, user_name: Current.executed_by.name, reason: captain_status_reason, locale: locale)
  end

  private

  def create_activity
    super
    with_account_locale { handle_auto_translate_change(determine_user_name) }
  end

  def handle_auto_translate_change(user_name) # rubocop:disable Metrics/CyclomaticComplexity
    return unless account.feature_enabled?('conversation_auto_translate') && user_name && saved_change_to_additional_attributes?

    before, after = previous_changes['additional_attributes']
    was_disabled = (before || {})['auto_translate_disabled'] == true
    now_disabled = (after || {})['auto_translate_disabled'] == true
    return if was_disabled == now_disabled

    change_type = now_disabled ? 'disabled' : 'enabled'
    content = I18n.t("conversations.activity.auto_translate.#{change_type}", user_name: user_name)
    enqueue_activity_message(activity_message_params(content, names: [user_name]))
  end

  def activity_message_params(content, content_attributes: nil, names: [])
    content_attributes = captain_control_activity_attributes(content_attributes)
    return super unless Current.executed_by.instance_of?(Captain::Assistant)

    attributes = (content_attributes || {}).deep_merge(activity: { source: { type: 'captain', name: Current.executed_by.name } })
    super(content, content_attributes: attributes, names: names)
  end

  def captain_control_activity_attributes(attributes)
    event = captain_control_event || captain_control_decision_key&.split(':')&.first
    return attributes unless event

    source = event == 'reopen' ? { type: 'contact' } : activity_source(determine_user_name)
    (attributes || {}).deep_merge(activity: { captain_event: event, source: source })
  end

  def status_activity_names(user_name, captain_content)
    return [Current.executed_by.name] if captain_content.blank? && Current.executed_by.instance_of?(Captain::Assistant)

    super
  end

  def captain_status_reason
    captain_activity_reason.presence
  end

  def captain_activity_key
    return captain_resolved_activity_key if resolved?
    return captain_open_activity_key if open?
  end

  def captain_resolved_activity_key
    return 'conversations.activity.captain.resolved_by_tool' if captain_activity_reason_type == :tool && captain_status_reason.present?
    return 'conversations.activity.captain.resolved_with_reason' if captain_status_reason.present?

    'conversations.activity.captain.resolved'
  end

  def captain_open_activity_key
    return 'conversations.activity.captain.open_with_reason' if captain_status_reason.present?

    'conversations.activity.captain.open'
  end
end
