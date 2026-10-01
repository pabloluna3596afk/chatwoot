class Captain::AppointmentsValidator < ActiveModel::Validator
  Settings = Captain::AppointmentsSettings

  def validate(record)
    raw = record.config['appointments']
    return if raw.nil?
    return record.errors.add(:config, 'appointments must be an object') unless raw.is_a?(Hash)
    return unless changed?(record, raw)

    settings = Settings.new(raw)
    validate_numbers(record, settings)
    validate_contact_fields(record, settings)
    validate_templates(record, settings)
    validate_calendar(record, settings) if settings.enabled?
  end

  private

  def validate_templates(record, settings)
    Settings::TEMPLATE_KEYS.each do |key|
      template = settings.values[key]
      next if template.nil?
      next if template.is_a?(Hash) && template['name'].present? && template['language'].present?

      record.errors.add(:config, "appointments #{key} must have a name and a language")
    end
  end

  def changed?(record, raw)
    previous = record.new_record? ? nil : record.config_was&.dig('appointments')
    previous.blank? || Settings.normalize(previous) != Settings.normalize(raw)
  end

  def validate_numbers(record, settings)
    {
      slot_duration_minutes: Settings::SLOT_DURATION_RANGE,
      min_notice_minutes: Settings::MIN_NOTICE_RANGE,
      booking_window_days: Settings::BOOKING_WINDOW_RANGE
    }.each do |key, range|
      value = settings.public_send(key)
      next if value.is_a?(Integer) && range.cover?(value)

      record.errors.add(:config, "appointments #{key} must be between #{range.min} and #{range.max}")
    end
  end

  def validate_contact_fields(record, settings)
    fields = settings.required_contact_fields
    return if fields.is_a?(Array) && (fields - Settings::CONTACT_FIELDS).empty?

    record.errors.add(:config, 'appointments required_contact_fields must be a subset of name, phone, email')
  end

  def validate_calendar(record, settings)
    connection_id = settings.calendar_connection_id
    connection = connection_id.is_a?(Integer) ? record.account.calendar_connections.active.find_by(id: connection_id) : nil
    return record.errors.add(:config, 'appointments calendar_connection_id is invalid') if connection.blank?
    return if settings.calendar_id.present? && connection.calendar_enabled?(settings.calendar_id)

    record.errors.add(:config, 'appointments calendar_id must be an enabled calendar of the connection')
  end
end
