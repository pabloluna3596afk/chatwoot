# Per-assistant appointment booking settings, stored under assistant.config['appointments'].
# normalize casts values and fills defaults; values that cannot be cast are kept as given so
# Captain::AppointmentsValidator can reject them instead of silently replacing them.
class Captain::AppointmentsSettings
  CONTACT_FIELDS = %w[name phone email].freeze
  SLOT_DURATION_RANGE = (5..240)
  MIN_NOTICE_RANGE = (0..10_080)
  BOOKING_WINDOW_RANGE = (1..90)
  INTEGER_KEYS = %w[calendar_connection_id slot_duration_minutes min_notice_minutes booking_window_days].freeze

  DEFAULTS = {
    'enabled' => false,
    'calendar_connection_id' => nil,
    'calendar_id' => nil,
    'slot_duration_minutes' => 30,
    'required_contact_fields' => CONTACT_FIELDS,
    'min_notice_minutes' => 60,
    'booking_window_days' => 14
  }.freeze

  def self.normalize(raw)
    raw = (raw.respond_to?(:to_h) ? raw.to_h : {}).stringify_keys.slice(*DEFAULTS.keys)
    DEFAULTS.to_h do |key, default|
      [key, raw.key?(key) ? cast(key, raw[key], default) : default.dup]
    end
  end

  def self.cast(key, value, default)
    return ActiveModel::Type::Boolean.new.cast(value) || false if key == 'enabled'
    return cast_fields(value, default) if key == 'required_contact_fields'
    return value.to_s.presence if key == 'calendar_id'
    return (value.blank? ? default : cast_integer(value)) if INTEGER_KEYS.include?(key)

    value
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
