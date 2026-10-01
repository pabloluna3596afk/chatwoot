class Captain::Tools::CheckAvailabilityTool < Captain::Tools::BaseAppointmentTool
  MAX_OPTIONS = 6
  DEFAULT_SPAN_DAYS = 7

  description 'Look up the free appointment times of the calendar. Returns up to 6 options, each with the exact start ' \
              'value to use when booking. Never invent times: only offer what this tool returns.'
  param :from_date, type: 'string', desc: 'First day to look at, YYYY-MM-DD (optional, defaults to today)', required: false
  param :to_date, type: 'string', desc: 'Last day to look at, YYYY-MM-DD (optional, defaults to a week after from_date)', required: false

  def perform(tool_context, from_date: nil, to_date: nil)
    conversation, error = conversation_for(tool_context)
    return error if error

    range = search_range(from_date, to_date)
    return translate('invalid_date') if range.nil?
    return translate('slots_none') if range.last <= range.first

    options = pick_options(available_slots(*range))
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
    first_day = from_date.present? ? Date.iso8601(from_date.to_s.strip) : zone.today
    last_day = to_date.present? ? Date.iso8601(to_date.to_s.strip) : first_day + DEFAULT_SPAN_DAYS
    range_start = zone.local(first_day.year, first_day.month, first_day.day)
    range_end = zone.local(last_day.year, last_day.month, last_day.day).end_of_day
    [range_start, [range_end, booking_limits.last].min]
  rescue ArgumentError
    nil
  end

  # Spreads the options over the days: the first and the middle slot of each day, in order.
  def pick_options(slots)
    slots.group_by { |slot| slot[:start][0, 10] }
         .values
         .flat_map { |day| [day.first, day[day.size / 2]].uniq }
         .first(MAX_OPTIONS)
  end

  def option_line(slot, number = nil)
    "#{number ? "#{number}." : '-'} #{format_time(Time.iso8601(slot[:start]))} (start=#{slot[:start]})"
  end
end
