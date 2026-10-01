class Captain::Tools::BookAppointmentTool < Captain::Tools::BaseAppointmentTool
  CONTACT_READERS = { 'name' => :name, 'phone' => :phone_number, 'email' => :email }.freeze

  description 'Book an appointment for the customer. Only call it after the customer has explicitly said yes to ONE specific ' \
              'time that check_availability returned; then pass customer_confirmed true and that exact start value. If contact ' \
              'details are missing the tool says which to ask for.'
  param :start, type: 'string',
                desc: 'The start of the time the customer confirmed: the exact value from check_availability, or the customer\'s button ' \
                      'reply text unchanged (e.g. "Sí, reservar · jue 16/01 10:00")'
  param :customer_confirmed, type: 'boolean', desc: 'true only if the customer explicitly confirmed this exact time', required: false
  param :name, type: 'string', desc: "The customer's full name, only if the tool asked for it", required: false
  param :phone, type: 'string', desc: "The customer's phone with country code, only if the tool asked for it", required: false
  param :email, type: 'string', desc: "The customer's email, only if the tool asked for it", required: false
  param :reason, type: 'string', desc: 'Short reason for the appointment, used as its title (optional)', required: false

  def perform(tool_context, start:, customer_confirmed: false, name: nil, phone: nil, email: nil, reason: nil)
    conversation, error = conversation_for(tool_context)
    return error if error
    return translate('confirm_required') unless customer_confirmed?(customer_confirmed)

    contact = conversation.contact
    contact_error = fill_contact(contact, name: name, phone: phone, email: email)
    return contact_error if contact_error

    missing = missing_fields(contact)
    return translate('missing_details', fields: missing.map { |field| translate("fields.#{field}") }.join(', ')) if missing.any?

    book(conversation, tool_context, contact, start, reason)
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def book(conversation, tool_context, contact, start, reason)
    resolved = resolve_start(conversation, start)
    return start_error(start) if resolved.nil?

    start_at = resolved[:start_at]
    return translate('outside_window', days: settings.booking_window_days) unless within_booking_limits?(start_at)

    end_at = start_at + settings.slot_duration_minutes.minutes
    booked = event_service.create(booking_params(conversation, contact, start_at, end_at, reason), enforce_hours: true)
    log_tool_usage('book_appointment', conversation_id: conversation.id, start: start_at.iso8601)
    follow_up(conversation, booked[:id])
    [translate(contact.email.present? ? 'booked_with_invite' : 'booked', time: format_time(start_at), email: contact.email),
     confirmation_hint(conversation, tool_context, booked[:id], start_at)].compact.join(' ')
  end

  # Reminders (24 h and 2 h before) are scheduled in Chatwoot for what Captain books. Scheduling twice for the
  # same event, as a retried call does, creates nothing new.
  def follow_up(conversation, event_id)
    return unless settings.reminder_24h? || settings.reminder_2h?

    record = connection.calendar_events.find_by(google_event_id: event_id)
    Captain::AppointmentReminders::Scheduler.schedule(record, assistant: @assistant, conversation: conversation) if record
  end

  # The confirmation is the model's own reply (one message, free inside the 24 h window), with [Cambiar hora]
  # [Cancelar cita] buttons when the channel has them.
  def confirmation_hint(conversation, tool_context, event_id, start_at)
    return unless settings.send_confirmation?

    values = %w[change_time cancel].index_with { |button| labelled_with_time(button, start_at) }
    items = values.map { |button, value| button_item(button, value) }
    buttons = offer_buttons(conversation, tool_context, items, values.values.index_with { { 'event_id' => event_id } })
    translate(buttons ? 'confirmation_buttons_hint' : 'confirmation_text_hint')
  end

  # No bot_followup_policy on purpose: Captain bookings must not notify Panel AI.
  def booking_params(conversation, contact, start_at, end_at, reason)
    {
      calendar_id: calendar_id,
      summary: reason.presence || translate('default_title', name: contact.name),
      start: start_at.iso8601,
      end: end_at.iso8601,
      contact_id: contact.id,
      conversation_id: conversation.display_id,
      attendee_email: contact.email.presence,
      idempotency_key: idempotency_key(conversation, start_at, end_at)
    }.merge(awaiting_confirmation? ? { appointment_status: 'pending_confirmation' } : {})
  end

  # Until the customer confirms (a button on the reminder), the appointment waits for it.
  def awaiting_confirmation?
    settings.send_confirmation? || settings.reminder_24h? || settings.reminder_2h?
  end

  # The same conversation booking the same slot twice is the same booking, so a retry of the
  # call returns the existing event instead of creating a second one.
  def idempotency_key(conversation, start_at, end_at)
    "captain-#{Digest::SHA256.hexdigest([conversation.id, calendar_id, start_at.to_i, end_at.to_i].join('|'))[0, 32]}"
  end

  def missing_fields(contact)
    settings.required_contact_fields.select { |field| contact.public_send(CONTACT_READERS.fetch(field)).blank? }
  end

  # Fills only the details the contact lacks; it never overwrites what is already known.
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
end
