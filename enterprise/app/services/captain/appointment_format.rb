# How Captain writes the date of an appointment to the customer, in the account language and timezone, without
# zero padding: "jueves 1 de octubre, 11:30" in a message and "jue 1 oct · 11:30" (at most 20 characters, what a
# WhatsApp button title allows) on a button. English: "Thursday, October 1, 11:30" and "Thu, Oct 1 · 11:30".
module Captain::AppointmentFormat
  module_function

  # "jueves 1 de octubre, 11:30"
  def long(time, locale:, zone:)
    render('date_long', time, locale, zone, names: :full)
  end

  # "jueves 1 de octubre"
  def day(time, locale:, zone:)
    render('date_only', time, locale, zone, names: :full)
  end

  # "jue 1 oct · 11:30"
  def short(time, locale:, zone:)
    render('date_short', time, locale, zone, names: :short)
  end

  # "11:30"
  def clock(time, zone:)
    time.in_time_zone(zone).strftime('%H:%M')
  end

  def render(format_key, time, locale, zone, names:)
    local = time.in_time_zone(zone)
    weekdays = I18n.t(names == :full ? 'captain.appointments.weekdays' : 'captain.appointments.weekdays_short', locale: locale)
    months = I18n.t(names == :full ? 'captain.appointments.months' : 'captain.appointments.months_short', locale: locale)
    I18n.t("captain.appointments.#{format_key}", locale: locale, weekday: weekdays[local.wday], day: local.day,
                                                 month: months[local.month - 1], time: clock(local, zone: zone))
  end
end
