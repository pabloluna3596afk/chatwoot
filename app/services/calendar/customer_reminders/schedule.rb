# The due instant is 24 hours before the appointment, advanced to 21:00 when it falls at night.
class Calendar::CustomerReminders::Schedule
  OPEN_HOUR = 8
  CLOSE_HOUR = 21

  def self.due_at(event)
    zone = Integrations::GoogleCalendar::Timezone.for(event.account)
    due = (event.start_at - CalendarEvent::CUSTOMER_REMINDER_LEAD_TIME).in_time_zone(zone)
    return due.change(hour: CLOSE_HOUR, min: 0, sec: 0) if due.hour >= CLOSE_HOUR
    return (due - 1.day).change(hour: CLOSE_HOUR, min: 0, sec: 0) if due.hour < OPEN_HOUR

    due
  end

  def self.sending_hours?(account, now)
    local = now.in_time_zone(Integrations::GoogleCalendar::Timezone.for(account))
    local.hour >= OPEN_HOUR && (local.hour < CLOSE_HOUR || (local.hour == CLOSE_HOUR && local.min.zero?))
  end
end
