class Captain::Tools::AppointmentListTool < Captain::Tools::BaseAppointmentTool
  description "List this customer's upcoming appointments with their ids. Use it before rescheduling or cancelling, " \
              'and only act on appointments this tool returns.'
  param :offer_changes, type: 'boolean', required: false,
                        desc: 'true when the customer asked to change or cancel an appointment: change/cancel/keep buttons are attached to your reply'

  def perform(tool_context, offer_changes: false)
    conversation, error = conversation_for(tool_context)
    return error if error

    tapped = tapped_button(conversation, tool_context)
    return answer_tap(tool_context, *tapped) if tapped

    appointments = own_appointments(conversation, conversation.contact)
    return translate('no_appointments') if appointments.empty?

    log_tool_usage('appointment_list', conversation_id: conversation.id, count: appointments.size)
    lines = [translate('appointments_header'), *appointments.map { |event| appointment_line(event) }]
    lines << changes_hint(conversation, tool_context, appointments) if explicit_true?(offer_changes)
    lines.join("\n")
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  # The customer tapped one of the change / cancel / keep buttons: the answer is the next step, never the same three
  # buttons again (a tap that is read as "the customer wants to change something" would loop).
  def answer_tap(tool_context, text, choice)
    log_tool_usage('appointment_list_tap', action: choice['action'])
    case choice['action']
    when 'change_time'
      Captain::Tools::CheckAvailabilityTool.new(@assistant).perform(tool_context, event_id: choice['event_id'])
    when 'cancel'
      translate('tap_cancel', text: text)
    else
      translate('tap_keep')
    end
  end

  def appointment_line(event)
    "- #{format_time(Time.iso8601(event[:start]))} | #{event[:summary]} | id=#{event[:id]}"
  end

  # The buttons act on one appointment, so they are offered only when the customer has exactly one.
  def changes_hint(conversation, tool_context, appointments)
    buttons = appointments.size == 1 && offer_change_buttons(conversation, tool_context, appointments.first[:id])
    translate(buttons ? 'manage_buttons_hint' : 'manage_text_hint',
              change: translate('buttons.change_time'), cancel: translate('buttons.cancel'), keep: translate('buttons.keep'))
  end

  # Titled and valued with the same readable text ("Cancelar cita"); the reply resolves to the appointment id.
  def offer_change_buttons(conversation, tool_context, event_id)
    items = %w[change_time cancel keep].map { |button| button_item(button, translate("buttons.#{button}")) }
    choices = %w[change_time cancel keep].zip(items).to_h { |button, item| [item['value'], appointment_choice(event_id, button)] }
    offer_buttons(conversation, tool_context, items, choices)
  end
end
