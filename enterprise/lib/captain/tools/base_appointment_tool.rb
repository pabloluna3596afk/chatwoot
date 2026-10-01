# Shared behavior of the Captain appointment tools: they only work in a conversation whose inbox
# has appointments active for the assistant, talk to the assistant's own calendar, and answer
# with short text (in the account language) that the model can relay to the customer.
class Captain::Tools::BaseAppointmentTool < Captain::Tools::BasePublicTool
  private

  def settings
    @assistant.appointments
  end

  # Resolves the conversation and checks that this channel may use appointments. Returns
  # [conversation, nil] or [nil, message for the model].
  def conversation_for(tool_context)
    conversation = find_conversation(tool_context.state)
    return [nil, 'Conversation not found'] unless conversation
    return [nil, translate('disabled')] unless @assistant.appointments_active_in?(conversation.inbox)
    return [nil, translate('no_calendar')] if connection.blank? || settings.calendar_id.blank?

    [conversation, nil]
  end

  def connection
    @connection ||= @assistant.account.calendar_connections.active.find_by(id: settings.calendar_connection_id)
  end

  # The assistant is the actor: it is not a User, so bookings are marked as made by AI and the
  # event lock is held under the assistant's own identity.
  def event_service
    @event_service ||= Integrations::GoogleCalendar::EventService.new(account: @assistant.account, user: @assistant, connection: connection)
  end

  def zone
    @zone ||= Time.find_zone!(@assistant.account.reporting_timezone.presence || Integrations::GoogleCalendar::Client::TIMEZONE)
  end

  def calendar_id
    settings.calendar_id
  end

  def translate(key, **options)
    I18n.t("captain.appointments.#{key}", locale: @assistant.account.locale, **options)
  end

  def format_time(time)
    local = time.in_time_zone(zone)
    weekday = I18n.t('captain.appointments.weekdays', locale: @assistant.account.locale)[local.wday]
    format('%<weekday>s %<day>02d/%<month>02d %<hour>s', weekday: weekday, day: local.day, month: local.month, hour: local.strftime('%H:%M'))
  end

  def parse_time(value)
    zone.parse(value.to_s.strip).presence
  rescue ArgumentError
    nil
  end

  # Earliest and latest start the customer may book, from the assistant's notice and window.
  def booking_limits
    now = Time.current.in_time_zone(zone)
    [now + settings.min_notice_minutes.minutes, now + settings.booking_window_days.days]
  end

  def within_booking_limits?(start_at)
    earliest, latest = booking_limits
    start_at >= earliest && start_at <= latest
  end

  def own_appointments(conversation, contact)
    Integrations::GoogleCalendar::EventService.contact_payloads(
      conversation.account, contact.id, calendar_id: calendar_id, time_min: Time.current.iso8601, time_max: 2.years.from_now.iso8601
    ).reject { |event| event[:deleted] }
  end

  def calendar_error_message(error)
    case error
    when Integrations::GoogleCalendar::EventService::SlotBusy then translate('slot_busy')
    when Integrations::GoogleCalendar::EventService::OutsideHours then translate('outside_hours')
    when Integrations::GoogleCalendar::EventService::InvalidRange then translate('invalid_start')
    when Integrations::GoogleCalendar::EventService::EventLocked then translate('busy_try_again')
    else
      Rails.logger.error("#{self.class.name}: #{error.class} #{error.message}")
      translate('calendar_unavailable')
    end
  end

  # Only an explicit true counts. ActiveModel casts unknown strings such as "no" to true, so it is not used here.
  def explicit_true?(value)
    value == true || value.to_s.strip.casecmp?('true')
  end

  def customer_confirmed?(value)
    explicit_true?(value)
  end

  # Stashes buttons for the reply the model is about to write (the response job sends them with it).
  # Returns false when the channel has no interactive messages, so the caller falls back to text.
  def offer_buttons(conversation, tool_context, items)
    return false unless Captain::QuickReplies.supported?(conversation.inbox)

    Captain::QuickReplies.stash(conversation, items, responding_to: tool_context.state[:responding_to_message_id])
    true
  end

  def button_item(button, value)
    Captain::QuickReplies.item(translate("buttons.#{button}"), value)
  end

  # "jue 16 · 10:00": short enough for a button (20 characters) in every language.
  def short_time(time)
    local = time.in_time_zone(zone)
    weekday = I18n.t('captain.appointments.weekdays_short', locale: @assistant.account.locale)[local.wday]
    "#{weekday} #{local.day} · #{local.strftime('%H:%M')}"
  end
end
