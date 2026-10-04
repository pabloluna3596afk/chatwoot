# Shared behavior of the Captain appointment tools: they only work in a conversation whose inbox
# has appointments active for the assistant, talk to the assistant's own calendar, and answer
# with short text (in the account language) that the model can relay to the customer.
class Captain::Tools::BaseAppointmentTool < Captain::Tools::BasePublicTool
  ISO_START = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/
  # A customer may ask for any start on this grid (10:15), not only for the back-to-back times the calendar lists.
  TIME_GRID_MINUTES = 15

  private

  def settings
    @assistant.appointments
  end

  # Resolves the conversation and checks that this channel may use appointments. Returns
  # [conversation, nil] or [nil, message for the model].
  def conversation_for(tool_context)
    conversation = find_conversation(tool_context.state)
    return [nil, 'Conversation not found'] unless conversation
    return [nil, translate('disabled')] unless @assistant.appointments_active_in?(conversation.inbox)
    return [nil, translate('no_calendar')] if connection.blank? || settings.calendar_id.blank?

    [conversation, nil]
  end

  def connection
    @connection ||= @assistant.account.calendar_connections.active.find_by(id: settings.calendar_connection_id)
  end

  # The assistant is the actor: it is not a User, so bookings are marked as made by AI and the
  # event lock is held under the assistant's own identity.
  def event_service
    @event_service ||= Integrations::GoogleCalendar::EventService.new(account: @assistant.account, user: @assistant, connection: connection)
  end

  def zone
    @zone ||= Time.find_zone!(@assistant.account.reporting_timezone.presence || Integrations::GoogleCalendar::Client::TIMEZONE)
  end

  def calendar_id
    settings.calendar_id
  end

  def translate(key, **options)
    I18n.t("captain.appointments.#{key}", locale: @assistant.account.locale, **options)
  end

  # "jueves 1 de octubre, 11:30" (account language and timezone, no zero padding)
  def format_time(time)
    Captain::AppointmentFormat.long(time, locale: @assistant.account.locale, zone: zone)
  end

  def parse_time(value)
    zone.parse(value.to_s.strip).presence
  rescue ArgumentError
    nil
  end

  # Earliest and latest start the customer may book, from the assistant's notice and window.
  def booking_limits
    now = Time.current.in_time_zone(zone)
    [now + settings.min_notice_minutes.minutes, now + settings.booking_window_days.days]
  end

  def within_booking_limits?(start_at)
    earliest, latest = booking_limits
    start_at >= earliest && start_at <= latest
  end

  # Whether an appointment of `minutes` starting at start_at is free in the calendar (hours, notice and busy times).
  def slot_free?(start_at, minutes)
    event_service.available_slots(
      calendar_id: calendar_id, from: start_at, to: start_at + minutes.minutes, duration: minutes,
      min_notice_minutes: settings.min_notice_minutes, step_minutes: TIME_GRID_MINUTES
    ).any? { |slot| slot[:start] == start_at.in_time_zone(zone).iso8601 }
  end

  # Why a time cannot be booked, as a key of captain.appointments (and its options), nil when it can.
  def unavailable_reason(start_at, minutes)
    return [:time_grid, {}] unless (start_at.min % TIME_GRID_MINUTES).zero?

    earliest, latest = booking_limits
    return [:too_soon, { minutes: settings.min_notice_minutes }] if start_at < earliest
    return [:outside_window, { days: settings.booking_window_days }] if start_at > latest
    return [:outside_hours, {}] unless event_service.within_hours?(calendar_id, start_at, start_at + minutes.minutes)

    [:slot_busy, {}] unless slot_free?(start_at, minutes)
  end

  def own_appointments(conversation, contact)
    Integrations::GoogleCalendar::EventService.contact_payloads(
      conversation.account, contact.id, calendar_id: calendar_id, time_min: Time.current.iso8601, time_max: 2.years.from_now.iso8601
    ).reject { |event| event[:deleted] }
  end

  def calendar_error_message(error)
    case error
    when Integrations::GoogleCalendar::EventService::SlotBusy then translate('slot_busy')
    when Integrations::GoogleCalendar::EventService::OutsideHours then translate('outside_hours')
    when Integrations::GoogleCalendar::EventService::InvalidRange then translate('invalid_start')
    when Integrations::GoogleCalendar::EventService::EventLocked then translate('busy_try_again')
    else
      Rails.logger.error("#{self.class.name}: #{error.class} #{error.message}")
      translate('calendar_unavailable')
    end
  end

  # Only an explicit true counts. ActiveModel casts unknown strings such as "no" to true, so it is not used here.
  def explicit_true?(value)
    value == true || value.to_s.strip.casecmp?('true')
  end

  def customer_confirmed?(value)
    explicit_true?(value)
  end

  # Stashes buttons for the reply the model is about to write (the response job sends them with it).
  # Returns false when the channel has no interactive messages, so the caller falls back to text.
  # `choices` maps each item's value to what it stands for ({'start' =>, 'event_id' =>}), so the reply resolves later.
  def offer_buttons(conversation, tool_context, items, choices = {})
    return false unless Captain::QuickReplies.supported?(conversation.inbox)

    Captain::QuickReplies.stash(
      conversation, items, responding_to: tool_context.state[:responding_to_message_id], choices: choices
    )
    true
  end

  def button_item(button, value)
    Captain::QuickReplies.item(translate("buttons.#{button}"), value)
  end

  # "jue 1 oct · 11:30"
  def short_date_time(time)
    Captain::AppointmentFormat.short(time, locale: @assistant.account.locale, zone: zone)
  end

  # The title of a time button, which is also its value and so the text of the customer's reply:
  # "jue 1 oct · 11:30" (at most 19 characters, under the 20 WhatsApp allows for a title).
  def slot_label(time)
    short_date_time(time)
  end

  # The value of a confirmation button, readable for the agents who see the reply: "Sí, reservar · jue 1 oct · 11:30".
  def labelled_with_time(button, time)
    "#{translate("buttons.#{button}")} · #{short_date_time(time)}"
  end

  # A start comes either as an ISO time or as the text of a button the customer tapped. Returns
  # { start_at:, event_id: } or nil.
  def resolve_start(conversation, value)
    choice = Captain::QuickReplies.choice(conversation, value)
    raw = choice&.dig('start') || value.to_s.strip
    return unless choice&.dig('start') || raw.match?(ISO_START)

    start_at = parse_time(raw)
    start_at && { start_at: start_at, event_id: choice&.dig('event_id') }
  end

  # Why a start could not be resolved: an unreadable ISO time, or a reply that is no longer (or never
  # was) one of the buttons, e.g. because the choices expired.
  def start_error(value)
    translate(value.to_s.strip.match?(ISO_START) ? 'invalid_start' : 'choice_expired')
  end

  CONTACT_READERS = { 'name' => :name, 'phone' => :phone_number, 'email' => :email }.freeze

  # The contact details the assistant requires that the contact still lacks.
  def missing_contact_fields(contact)
    settings.required_contact_fields.select { |field| contact.public_send(CONTACT_READERS.fetch(field)).blank? }
  end

  def missing_fields_text(fields)
    fields.map { |field| translate("fields.#{field}") }.join(', ')
  end

  # Fills only the details the contact lacks; it never overwrites what is already known. Returns a message for the
  # model when a value cannot be saved, nil otherwise.
  def fill_contact(contact, name:, phone:, email:)
    attributes = {}
    attributes[:name] = name.strip if contact.name.blank? && name.present?
    attributes[:email] = email.strip.downcase if contact.email.blank? && email.present?
    attributes[:phone_number] = normalize_phone(phone) if contact.phone_number.blank? && phone.present?
    return if attributes.empty?

    contact.update!(attributes)
    nil
  rescue ActiveRecord::RecordInvalid => e
    translate('invalid_contact', fields: field_labels(e.record.errors.attribute_names))
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/[\s\-().]/, '')
  end

  def field_labels(attributes)
    attributes.map do |attribute|
      key = attribute == :phone_number ? 'phone' : attribute.to_s
      translate("fields.#{key}", default: key)
    end.join(', ')
  end

  # What went wrong AFTER the event exists is not a calendar failure: the booking stands. It is reported (so it gets
  # looked at) and the reply carries on.
  def report_side_failure(error)
    Rails.logger.error("#{self.class.name}: #{error.class} #{error.message}")
    ChatwootExceptionTracker.new(error, account: @assistant.account).capture_exception
    nil
  end

  # An appointment id, or the text of the change/cancel/keep button that stands for it.
  def resolve_event_id(conversation, value)
    choice = Captain::QuickReplies.choice(conversation, value)
    choice ? choice['event_id'] : value.to_s.strip.presence
  end
end
