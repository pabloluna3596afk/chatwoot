class Captain::Tools::ProposeAppointmentTool < Captain::Tools::BaseAppointmentTool
  description 'Call it right before asking the customer to confirm ONE specific time, either to book it or to move an existing ' \
              'appointment. It checks the time is still free and attaches the confirmation buttons to your reply. It never books: ' \
              'only an explicit yes from the customer does, through book_appointment or reschedule_appointment.'
  param :start, type: 'string', desc: 'The exact start value of the time you are proposing, from check_availability'
  param :event_id, type: 'string', desc: 'Only when moving an existing appointment: its id from appointment_list', required: false

  def perform(tool_context, start:, event_id: nil)
    conversation, error = conversation_for(tool_context)
    return error if error

    start_at = parse_time(start)
    return translate('invalid_start') if start_at.blank?
    return translate('outside_window', days: settings.booking_window_days) unless within_booking_limits?(start_at)

    event = own_event(conversation, event_id)
    return translate('not_found') if event_id.present? && event.blank?
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
    buttons = offer_buttons(conversation, tool_context, confirmation_items(start_at, event))
    kind = event ? 'propose_reschedule' : 'propose'
    log_tool_usage('propose_appointment', conversation_id: conversation.id, start: start_at.iso8601)
    translate("#{kind}_#{buttons ? 'buttons' : 'text'}", time: format_time(start_at))
  end

  def confirmation_items(start_at, event)
    yes = if event
            button_item('yes_reschedule', "yes_reschedule:#{event[:id]}:#{start_at.iso8601}")
          else
            button_item('yes_book', "yes_book:#{start_at.iso8601}")
          end
    [yes, button_item('other_time', 'other_time')]
  end
end
