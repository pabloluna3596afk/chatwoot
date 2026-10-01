class Captain::Tools::CancelAppointmentTool < Captain::Tools::BaseAppointmentTool
  description "Cancel one of the customer's own appointments. Get the id from appointment_list, ask the customer to confirm " \
              'the cancellation, then call it with customer_confirmed true.'
  param :event_id, type: 'string', desc: 'The id of the appointment, from appointment_list'
  param :customer_confirmed, type: 'boolean', desc: 'true only if the customer explicitly confirmed the cancellation', required: false

  def perform(tool_context, event_id:, customer_confirmed: false)
    conversation, error = conversation_for(tool_context)
    return error if error

    event = own_appointments(conversation, conversation.contact).find { |item| item[:id] == event_id.to_s }
    return translate('not_found') if event.blank?
    return translate('confirm_required') unless customer_confirmed?(customer_confirmed)

    event_service.destroy(event[:id], calendar_id: calendar_id, note: translate('cancel_note', assistant: @assistant.name))
    log_tool_usage('cancel_appointment', conversation_id: conversation.id, event_id: event[:id])
    translate('cancelled', time: format_time(Time.iso8601(event[:start])))
  rescue StandardError => e
    calendar_error_message(e)
  end
end
