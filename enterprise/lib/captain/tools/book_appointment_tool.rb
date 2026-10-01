class Captain::Tools::BookAppointmentTool < Captain::Tools::BaseAppointmentTool
  CONTACT_READERS = { 'name' => :name, 'phone' => :phone_number, 'email' => :email }.freeze

  description 'Book an appointment for the customer. Only call it after the customer has explicitly said yes to ONE specific ' \
              'time that check_availability returned; then pass customer_confirmed true and that exact start value. If contact ' \
              'details are missing the tool says which to ask for.'
  param :start, type: 'string', desc: 'The exact start value of the time the customer confirmed, from check_availability'
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

    book(conversation, contact, start, reason)
  rescue StandardError => e
    calendar_error_message(e)
  end

  private

  def book(conversation, contact, start, reason)
    start_at = parse_time(start.to_s.sub(/\Ayes_book:/, ''))
    return translate('invalid_start') if start_at.blank?
    return translate('outside_window', days: settings.booking_window_days) unless within_booking_limits?(start_at)

    end_at = start_at + settings.slot_duration_minutes.minutes
    event_service.create(booking_params(conversation, contact, start_at, end_at, reason), enforce_hours: true)
    log_tool_usage('book_appointment', conversation_id: conversation.id, start: start_at.iso8601)
    translate(contact.email.present? ? 'booked_with_invite' : 'booked', time: format_time(start_at), email: contact.email)
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
    }
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
