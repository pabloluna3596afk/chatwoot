class Captain::Tools::ConfirmAppointmentTool < Captain::Tools::BaseAppointmentTool
  description "Mark one of the customer's own appointments as confirmed. Call it when the customer taps or writes the confirm button " \
              'of a reminder (e.g. "Confirmo · jue 16/01 10:00"). It needs no further question to the customer.'
  param :event_id, type: 'string',
                   desc: 'The id of the appointment, from appointment_list, or the customer\'s button reply text unchanged (e.g. "Confirmo · jue 16/01 10:00")'

  def perform(tool_context, event_id:)
    conversation, error = conversation_for(tool_context)
    return error if error

    event_ref = resolve_event_id(conversation, event_id)
    event = own_appointments(conversation, conversation.contact).find { |item| item[:id] == event_ref.to_s }
    return translate('not_found') if event.blank?

    confirm(event)
    log_tool_usage('confirm_appointment', conversation_id: conversation.id, event_id: event[:id])
    translate('confirmed', time: format_time(Time.iso8601(event[:start])))
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  # Only the local status changes: the event in Google Calendar is the same, so nothing is sent to it.
  def confirm(event)
    record = connection.calendar_events.kept.find_by(google_event_id: event[:id])
    record&.update!(appointment_status: 'confirmed')
  end
end
