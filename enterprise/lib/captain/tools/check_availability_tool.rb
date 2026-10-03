class Captain::Tools::CheckAvailabilityTool < Captain::Tools::BaseAppointmentTool
  MAX_OPTIONS = 3
  DEFAULT_SPAN_DAYS = 14
  # Local hours [from, to) of each part of the day a customer can ask for ("en la mañana", "en la tarde"...).
  PARTS_OF_DAY = { 'morning' => (0...12), 'afternoon' => (12...18), 'evening' => (18...24) }.freeze

  description 'Look up the free appointment times of the calendar. Returns up to 3 options, each with the exact start ' \
              'value to use when booking. Pass what the customer asked for: the day (from_date and to_date, the same day for ' \
              '"tomorrow" or "on Friday") and the part of the day. With nothing specific it offers the next day that has ' \
              'availability. Never invent times: only offer what this tool returns.'
  param :from_date, type: 'string', desc: 'First day to look at, YYYY-MM-DD (optional, defaults to today)', required: false
  param :to_date, type: 'string',
                  desc: 'Last day to look at, YYYY-MM-DD (optional; leave it out to get the next day with availability)', required: false
  param :part_of_day, type: 'string', required: false,
                      desc: 'morning (before 12:00), afternoon (12:00 to 18:00) or evening (after 18:00), when the customer asked for one'

  def perform(tool_context, from_date: nil, to_date: nil, part_of_day: nil)
    conversation, error = conversation_for(tool_context)
    return error if error

    range = search_range(from_date, to_date)
    return translate('invalid_date') if range.nil?
    return translate('slots_none') if range.last <= range.first

    options = pick_options(in_part_of_day(available_slots(*range), part_of_day), single_day: from_date.present? && to_date.blank?)
    return translate('slots_none') if options.empty?

    log_tool_usage('check_availability', assistant_id: @assistant.id, options: options.size)
    slots_message(conversation, tool_context, options)
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  # One button (or list row) per slot, titled and valued with its readable label ("jue 16/01 · 10:00"),
  # which resolves back to the exact start. Channels without buttons get a numbered list the model writes itself.
  def slots_message(conversation, tool_context, options)
    labels = options.to_h { |slot| [slot_label(Time.iso8601(slot[:start])), { 'start' => slot[:start] }] }
    items = labels.keys.map { |label| Captain::QuickReplies.item(label, label) }
    buttons = offer_buttons(conversation, tool_context, items, labels)
    lines = options.each_with_index.map { |slot, index| option_line(slot, buttons ? nil : index + 1) }
    [translate('slots_header', timezone: zone.tzinfo.name), *lines, translate(buttons ? 'slots_buttons_hint' : 'slots_numbered_hint')].join("\n")
  end

  def available_slots(range_start, range_end)
    event_service.available_slots(
      calendar_id: calendar_id, from: range_start, to: range_end,
      duration: settings.slot_duration_minutes, min_notice_minutes: settings.min_notice_minutes
    )
  end

  # Returns [from, to] clamped to the booking window, or nil when a date cannot be read.
  def search_range(from_date, to_date)
    @explicit_range = from_date.present? && to_date.present? && from_date.to_s.strip != to_date.to_s.strip
    first_day = from_date.present? ? Date.iso8601(from_date.to_s.strip) : zone.today
    last_day = to_date.present? ? Date.iso8601(to_date.to_s.strip) : first_day + DEFAULT_SPAN_DAYS
    range_start = zone.local(first_day.year, first_day.month, first_day.day)
    range_end = zone.local(last_day.year, last_day.month, last_day.day).end_of_day
    [range_start, [range_end, booking_limits.last].min]
  rescue ArgumentError
    nil
  end

  def in_part_of_day(slots, part_of_day)
    hours = PARTS_OF_DAY[part_of_day.to_s.strip.downcase]
    return slots if hours.nil?

    slots.select { |slot| hours.cover?(Time.iso8601(slot[:start]).in_time_zone(zone).hour) }
  end

  # Up to 3 options. With a single day (or nothing specific) they are spread over the first day that has
  # availability, so the customer chooses a time and not a day; over several days, the first slot of each of the
  # first days.
  def pick_options(slots, single_day: false)
    days = slots.group_by { |slot| slot[:start][0, 10] }.values
    return [] if days.empty?
    return spread(days.first) if single_day || days.size == 1 || @explicit_range.blank?

    days.first(MAX_OPTIONS).map(&:first)
  end

  # Evenly spread slots of a day: the first, the middle and the last.
  def spread(day)
    [day.first, day[day.size / 2], day.last].uniq.first(MAX_OPTIONS)
  end

  def option_line(slot, number = nil)
    "#{number ? "#{number}." : '-'} #{format_time(Time.iso8601(slot[:start]))} (start=#{slot[:start]})"
  end
end
