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
  param :event_id, type: 'string', required: false,
                   desc: 'Only when the customer wants to move an existing appointment: its id from appointment_list, or the reply ' \
                         '"Cambiar hora" unchanged. The times offered then move THAT appointment.'
  param :at_time, type: 'string', required: false,
                  desc: 'The exact time the customer asked for, HH:MM in 24 hours (for example "10:15"), together with from_date. ' \
                        'Any start on a 15 minute grid is accepted when it is free; when it is not, the answer says why in one line ' \
                        'and lists the closest times.'

  # The signature is the tool's parameters, so the long list cannot be shortened.
  def perform(tool_context, from_date: nil, to_date: nil, part_of_day: nil, at_time: nil, event_id: nil) # rubocop:disable Metrics/ParameterLists
    conversation, error = conversation_for(tool_context)
    return error if error

    @moving, missing = moved_appointment(conversation, event_id)
    return missing if missing
    return requested_time_message(conversation, tool_context, from_date, at_time) if at_time.present?

    listed_times_message(conversation, tool_context, from_date, to_date, part_of_day)
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def listed_times_message(conversation, tool_context, from_date, to_date, part_of_day)
    range = search_range(from_date, to_date)
    return translate('invalid_date') if range.nil?
    return translate('slots_none') if range.last <= range.first

    options = pick_options(in_part_of_day(available_slots(*range), part_of_day), single_day: from_date.present? && to_date.blank?)
    return translate('slots_none') if options.empty?

    log_tool_usage('check_availability', assistant_id: @assistant.id, options: options.size)
    slots_message(conversation, tool_context, options)
  end

  # [the customer's appointment being moved, nil] / [nil, message for the model] / [nil, nil] when none is moved.
  def moved_appointment(conversation, event_id)
    return [nil, nil] if event_id.blank?

    ref = resolve_event_id(conversation, event_id)
    event = own_appointments(conversation, conversation.contact).find { |item| item[:id] == ref.to_s }
    event ? [event, nil] : [nil, translate('not_found')]
  end

  # The customer asked for an exact time: it is offered as it is when it is free (and on the 15 minute grid); when it is
  # not, one line says why and the closest free times follow.
  def requested_time_message(conversation, tool_context, from_date, at_time)
    start_at = requested_start(from_date, at_time)
    return translate('invalid_time') if start_at.nil?

    reason, reason_options = unavailable_reason(start_at, settings.slot_duration_minutes)
    return exact_time_message(conversation, tool_context, start_at) if reason.nil?

    options = closest_options(start_at)
    return "#{translate(reason, **reason_options)}\n#{translate('slots_none')}" if options.empty?

    [translate(reason, **reason_options), translate('closest_header'), slots_message(conversation, tool_context, options)].join("\n")
  end

  def requested_start(from_date, at_time)
    day = Date.iso8601(from_date.to_s.strip)
    hour, minute = clock_parts(at_time)
    zone.local(day.year, day.month, day.day, hour, minute) if hour
  rescue ArgumentError
    nil
  end

  # [hour, minute] of "HH:MM" (24 hours), nil when it is not a time.
  def clock_parts(at_time)
    hour, minute = at_time.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)&.captures&.map(&:to_i)
    [hour, minute] if hour&.<=(23) && minute <= 59
  end

  def exact_time_message(conversation, tool_context, start_at)
    option = { start: start_at.iso8601 }
    log_tool_usage('check_availability', assistant_id: @assistant.id, options: 1, exact: true)
    [translate('exact_time_free', time: format_time(start_at)), slots_message(conversation, tool_context, [option])].join("\n")
  end

  # The 3 free times nearest to the requested one that day; when the day has none, the next days that have.
  def closest_options(start_at)
    day = available_slots(start_at.beginning_of_day, start_at.end_of_day)
    return day.min_by(MAX_OPTIONS) { |slot| (Time.iso8601(slot[:start]) - start_at).abs }.sort_by { |slot| slot[:start] } if day.any?

    earliest, latest = booking_limits
    pick_options(available_slots([start_at.beginning_of_day, earliest].max, latest))
  end

  # One button (or list row) per slot, titled and valued with its readable label ("jue 16/01 · 10:00"),
  # which resolves back to the exact start. Channels without buttons get a numbered list the model writes itself.
  def slots_message(conversation, tool_context, options)
    labels = options.to_h { |slot| [slot_label(Time.iso8601(slot[:start])), slot_choice(slot)] }
    items = labels.keys.map { |label| Captain::QuickReplies.item(label, label) }
    buttons = offer_buttons(conversation, tool_context, items, labels)
    lines = options.each_with_index.map { |slot, index| option_line(slot, buttons ? nil : index + 1) }
    [moving_line, translate('slots_header', timezone: zone.tzinfo.name), *lines,
     translate(buttons ? 'slots_buttons_hint' : 'slots_numbered_hint')].compact.join("\n")
  end

  # The button of a time carries the appointment being moved, so choosing it leads to "move it to ...".
  def slot_choice(slot)
    { 'start' => slot[:start] }.merge(@moving ? { 'event_id' => @moving[:id] } : {})
  end

  def moving_line
    translate('moving_header', time: format_time(Time.iso8601(@moving[:start]))) if @moving
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
