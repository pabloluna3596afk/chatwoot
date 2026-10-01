class Captain::Tools::AppointmentListTool < Captain::Tools::BaseAppointmentTool
  description "List this customer's upcoming appointments with their ids. Use it before rescheduling or cancelling, " \
              'and only act on appointments this tool returns.'

  def perform(tool_context)
    conversation, error = conversation_for(tool_context)
    return error if error

    appointments = own_appointments(conversation, conversation.contact)
    return translate('no_appointments') if appointments.empty?

    log_tool_usage('appointment_list', conversation_id: conversation.id, count: appointments.size)
    [translate('appointments_header'), *appointments.map { |event| appointment_line(event) }].join("\n")
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def appointment_line(event)
    "- #{format_time(Time.iso8601(event[:start]))} | #{event[:summary]} | id=#{event[:id]}"
  end
end
