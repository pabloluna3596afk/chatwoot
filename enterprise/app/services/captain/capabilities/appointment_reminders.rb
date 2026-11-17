class Captain::Capabilities::AppointmentReminders < Captain::Capabilities::Base
  def call
    booking = Captain::Capabilities::Booking.new(assistant, inbox).call
    return result(booking[:status], booking[:reason]) unless booking[:status] == 'ready'
    return result('off', 'disabled') unless assistant.appointments.any_reminder_enabled?
    return result('ready', 'window_only') if inbox && Captain::AppointmentReminders::Readiness.new(assistant, inbox).outside_window_reason

    result('ready')
  end
end
