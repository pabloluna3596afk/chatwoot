class Captain::Capabilities::Booking < Captain::Capabilities::Base
  def call
    return result('not_connected', 'not_connected_calendar') unless active_connections.exists?
    return result('off', 'disabled') unless assistant.appointments.enabled?

    connection = selected_calendar
    return result('needs_setup', 'no_calendar_selected') unless connection&.calendar_enabled?(assistant.appointments.calendar_id)
    return result('off', 'disabled') if inbox_appointments_disabled?

    result('ready')
  end

  private

  def active_connections
    assistant.account.calendar_connections.active
  end

  def selected_calendar
    active_connections.find_by(id: assistant.appointments.calendar_connection_id)
  end

  def inbox_appointments_disabled?
    return false unless inbox

    !assistant.captain_inboxes.find_by(inbox_id: inbox.id)&.appointments_enabled
  end
end
