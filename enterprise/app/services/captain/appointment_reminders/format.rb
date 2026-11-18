class Captain::AppointmentReminders::Format
  def initialize(event, locale:, zone:)
    @event = event
    @locale = locale
    @zone = zone
  end

  def long
    Captain::AppointmentFormat.long(@event.start_at, locale: @locale, zone: @zone)
  end

  def short
    Captain::AppointmentFormat.short(@event.start_at, locale: @locale, zone: @zone)
  end

  def drop
    {
      'date' => Captain::AppointmentFormat.day(@event.start_at, locale: @locale, zone: @zone),
      'time' => Captain::AppointmentFormat.clock(@event.start_at, zone: @zone),
      'datetime' => long,
      'title' => @event.summary
    }
  end
end
