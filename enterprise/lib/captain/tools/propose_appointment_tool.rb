class Captain::Tools::ProposeAppointmentTool < Captain::Tools::BaseAppointmentTool
  description 'Call it right before asking the customer to confirm ONE specific time, either to book it or to move an existing ' \
              'appointment. It checks the time is still free and attaches the confirmation buttons to your reply. It never books: ' \
              'only an explicit yes from the customer does, through book_appointment or reschedule_appointment.'
  param :start, type: 'string',
                desc: 'The time you are proposing: the exact start value from check_availability, or the customer\'s button reply text ' \
                      'unchanged (e.g. "jue 16/01 · 10:00")'
  param :event_id, type: 'string', required: false,
                   desc: 'Only when moving an existing appointment: its id from appointment_list, or the reply "Cambiar hora" unchanged'

  def perform(tool_context, start:, event_id: nil)
    conversation, error = conversation_for(tool_context)
    return error if error

    resolved = resolve_start(conversation, start)
    return start_error(start) if resolved.nil?

    start_at = resolved[:start_at]
    return translate('outside_window', days: settings.booking_window_days) unless within_booking_limits?(start_at)

    event_ref = resolve_event_id(conversation, event_id) || resolved[:event_id]
    event = own_event(conversation, event_ref)
    return translate('not_found') if event_ref.present? && event.blank?
    return translate('slot_busy') unless free?(start_at, event)

    proposal(conversation, tool_context, start_at, event)
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def own_event(conversation, event_id)
    return if event_id.blank?

    own_appointments(conversation, conversation.contact).find { |item| item[:id] == event_id.to_s }
  end

  def minutes(event)
    return settings.slot_duration_minutes if event.blank?

    ((Time.iso8601(event[:end]) - Time.iso8601(event[:start])) / 60).to_i
  end

  def free?(start_at, event)
    event_service.available_slots(
      calendar_id: calendar_id, from: start_at, to: start_at + minutes(event).minutes,
      duration: minutes(event), min_notice_minutes: settings.min_notice_minutes
    ).any? { |slot| slot[:start] == start_at.in_time_zone(zone).iso8601 }
  end

  def proposal(conversation, tool_context, start_at, event)
    yes_button = event ? 'yes_reschedule' : 'yes_book'
    yes_value = labelled_with_time(yes_button, start_at)
    items = [button_item(yes_button, yes_value), button_item('other_time', translate('buttons.other_time'))]
    choice = { 'start' => start_at.iso8601 }.merge(event ? { 'event_id' => event[:id] } : {})
    buttons = offer_buttons(conversation, tool_context, items, { yes_value => choice })
    log_tool_usage('propose_appointment', conversation_id: conversation.id, start: start_at.iso8601)
    translate("#{event ? 'propose_reschedule' : 'propose'}_#{buttons ? 'buttons' : 'text'}",
              time: format_time(start_at), yes: translate("buttons.#{yes_button}"), other: translate('buttons.other_time'))
  end
end
