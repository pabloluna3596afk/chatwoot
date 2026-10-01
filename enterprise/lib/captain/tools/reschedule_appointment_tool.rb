class Captain::Tools::RescheduleAppointmentTool < Captain::Tools::BaseAppointmentTool
  description "Move one of the customer's own appointments to another time. Get the id from appointment_list and the new " \
              'time from check_availability, ask the customer to confirm, then call it with customer_confirmed true.'
  param :new_start, type: 'string',
                    desc: 'The new start: the exact value from check_availability, or the customer\'s button reply text unchanged ' \
                          '(e.g. "Sí, cambiarla · jue 16/01 10:00")'
  param :event_id, type: 'string', required: false,
                   desc: 'The id of the appointment, from appointment_list. Optional when the reply to a "move it" button carries it'
  param :customer_confirmed, type: 'boolean', desc: 'true only if the customer explicitly confirmed the new time', required: false

  def perform(tool_context, new_start:, event_id: nil, customer_confirmed: false)
    conversation, error = conversation_for(tool_context)
    return error if error

    resolved = resolve_start(conversation, new_start)
    return start_error(new_start) if resolved.nil?

    event_ref = resolve_event_id(conversation, event_id) || resolved[:event_id]
    event = own_appointments(conversation, conversation.contact).find { |item| item[:id] == event_ref.to_s }
    return translate('not_found') if event.blank?
    return translate('confirm_required') unless customer_confirmed?(customer_confirmed)

    reschedule(conversation, event, resolved[:start_at])
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def reschedule(conversation, event, start_at)
    return translate('outside_window', days: settings.booking_window_days) unless within_booking_limits?(start_at)

    end_at = start_at + (Time.iso8601(event[:end]) - Time.iso8601(event[:start]))
    event_service.update(event[:id], update_params(conversation, event, start_at, end_at), enforce_hours: true)
    log_tool_usage('reschedule_appointment', conversation_id: conversation.id, event_id: event[:id])
    translate('rescheduled', time: format_time(start_at))
  end

  def update_params(conversation, event, start_at, end_at)
    contact = conversation.contact
    {
      calendar_id: calendar_id,
      summary: event[:summary],
      start: start_at.iso8601,
      end: end_at.iso8601,
      contact_id: contact.id,
      conversation_id: conversation.display_id,
      attendee_email: contact.email.presence
    }
  end
end
