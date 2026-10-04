# Per-assistant appointment booking settings, stored under assistant.config['appointments'].
# normalize casts values and fills defaults; values that cannot be cast are kept as given so
# Captain::AppointmentsValidator can reject them instead of silently replacing them.
class Captain::AppointmentsSettings
  CONTACT_FIELDS = %w[name phone email].freeze
  SLOT_DURATION_RANGE = (5..240)
  MIN_NOTICE_RANGE = (0..10_080)
  BOOKING_WINDOW_RANGE = (1..90)
  REMINDER_HOURS_RANGE = (1..168)
  INTEGER_KEYS = %w[calendar_connection_id slot_duration_minutes min_notice_minutes booking_window_days].freeze
  REMINDER_KEYS = %w[reminder_1 reminder_2].freeze
  TEMPLATE_KEYS = %w[template_reminder template_cancelled].freeze
  # Settings (and reminder rows) saved before the reminders were editable: a switch each, 24 h and 2 h.
  LEGACY_REMINDERS = { 'reminder_1' => ['reminder_24h', 24], 'reminder_2' => ['reminder_2h', 2] }.freeze
  LEGACY_KINDS = { 'reminder_24h' => 'reminder_1', 'reminder_2h' => 'reminder_2' }.freeze

  # The confirmation is always Captain's own reply right after the customer's yes (free, inside the 24 h window).
  # Two reminders, each with its own lead time, are free-form when the customer wrote in the last 24 h; WhatsApp
  # bills a template sent outside that window, so templates stay off until the owner turns on the assistant's
  # allow_paid_templates.
  DEFAULTS = {
    'enabled' => false,
    'calendar_connection_id' => nil,
    'calendar_id' => nil,
    'slot_duration_minutes' => 30,
    'required_contact_fields' => CONTACT_FIELDS,
    'min_notice_minutes' => 60,
    'booking_window_days' => 14,
    'reminder_1' => { 'enabled' => true, 'hours_before' => 24 },
    'reminder_2' => { 'enabled' => true, 'hours_before' => 3 },
    'template_reminder' => nil,
    'template_cancelled' => nil
  }.freeze

  def self.normalize(raw)
    raw = (raw.respond_to?(:to_h) ? raw.to_h : {}).stringify_keys
    DEFAULTS.to_h do |key, default|
      [key, key_given?(raw, key) ? cast(key, given_value(raw, key), default) : default.deep_dup]
    end
  end

  def self.key_given?(raw, key)
    raw.key?(key) || (REMINDER_KEYS.include?(key) && raw.key?(LEGACY_REMINDERS[key].first))
  end

  # A reminder saved the old way (a boolean under reminder_24h / reminder_2h) keeps its old lead time.
  def self.given_value(raw, key)
    return raw[key] if raw.key?(key)

    legacy_key, hours = LEGACY_REMINDERS[key]
    { 'enabled' => raw[legacy_key], 'hours_before' => hours }
  end

  def self.cast(key, value, default)
    return cast_reminder(value, default) if REMINDER_KEYS.include?(key)
    return strict_boolean(value) if key == 'enabled'
    return cast_fields(value, default) if key == 'required_contact_fields'
    return value.to_s.presence if key == 'calendar_id'
    return Captain::TemplateReference.cast(value) if TEMPLATE_KEYS.include?(key)
    return (value.blank? ? default : cast_integer(value)) if INTEGER_KEYS.include?(key)

    value
  end

  # { 'enabled' => bool, 'hours_before' => Integer }; anything else is kept for the validator to reject.
  def self.cast_reminder(value, default)
    return value unless value.respond_to?(:to_h) && !value.is_a?(Array) && !value.is_a?(String)

    reminder = value.to_h.stringify_keys
    {
      'enabled' => reminder.key?('enabled') ? strict_boolean(reminder['enabled']) : default['enabled'],
      'hours_before' => reminder['hours_before'].blank? ? default['hours_before'] : cast_integer(reminder['hours_before'])
    }
  end

  # Only true / "true" / "1" / 1 count: ActiveModel would read "no" as true.
  def self.strict_boolean(value)
    [true, 'true', '1', 1].include?(value)
  end

  def self.cast_integer(value)
    Integer(value.to_s, exception: false) || value
  end

  def self.cast_fields(value, default)
    return default.dup if value.nil?

    Array(value).map(&:to_s).uniq
  end

  attr_reader :values

  def initialize(raw = nil)
    @values = self.class.normalize(raw)
  end

  def enabled?
    values['enabled'] == true
  end

  # The reminders in order: [{ 'kind' => 'reminder_1', 'enabled' => true, 'hours_before' => 24 }, ...]
  def reminders
    REMINDER_KEYS.map { |kind| { 'kind' => kind }.merge(values[kind]) }
  end

  # `kind` is a reminder_1 / reminder_2 (or a legacy reminder_24h / reminder_2h of a row scheduled before).
  def reminder(kind)
    values[LEGACY_KINDS.fetch(kind, kind)]
  end

  def reminder_enabled?(kind)
    reminder(kind)['enabled'] == true
  end

  def hours_before(kind)
    reminder(kind)['hours_before']
  end

  def any_reminder_enabled?
    REMINDER_KEYS.any? { |kind| reminder_enabled?(kind) }
  end

  def template_reminder
    values['template_reminder']
  end

  def template_cancelled
    values['template_cancelled']
  end

  def calendar_connection_id
    values['calendar_connection_id']
  end

  def calendar_id
    values['calendar_id']
  end

  def slot_duration_minutes
    values['slot_duration_minutes']
  end

  def required_contact_fields
    values['required_contact_fields']
  end

  def min_notice_minutes
    values['min_notice_minutes']
  end

  def booking_window_days
    values['booking_window_days']
  end

  def to_h
    values.deep_dup
  end
end
