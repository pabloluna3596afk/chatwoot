# Per-assistant follow-up settings, stored under assistant.config['followup'].
#
# Inactivity: after `inactivity_after_minutes` without a reply to Captain's last message, Captain sends up
# to `max_nudges` short "¿Sigues ahí?" messages (free, inside the 24 h window) and, `close_after_minutes`
# after the last one with no answer, closes the conversation. Re-engagement is off by default: after the
# window closes it is always an approved WhatsApp template, which Meta bills, so it also needs the
# assistant's "paid templates" switch.
#
# normalize casts values and fills defaults; values that cannot be cast are kept as given so
# Captain::FollowupValidator can reject them instead of silently replacing them.
class Captain::FollowupSettings
  INACTIVITY_AFTER_RANGE = (5..1440)
  MAX_NUDGES_RANGE = (0..2)
  CLOSE_AFTER_RANGE = (5..1440)
  INTEGER_KEYS = %w[inactivity_after_minutes max_nudges close_after_minutes].freeze
  BOOLEAN_KEYS = %w[inactivity_enabled reengagement_enabled].freeze

  DEFAULTS = {
    'inactivity_enabled' => true,
    'inactivity_after_minutes' => 30,
    'max_nudges' => 1,
    'close_after_minutes' => 120,
    'reengagement_enabled' => false,
    'reengagement_template' => nil
  }.freeze

  def self.normalize(raw)
    raw = (raw.respond_to?(:to_h) ? raw.to_h : {}).stringify_keys.slice(*DEFAULTS.keys)
    DEFAULTS.to_h do |key, default|
      [key, raw.key?(key) ? cast(key, raw[key], default) : default.dup]
    end
  end

  def self.cast(key, value, default)
    return strict_boolean(value) if BOOLEAN_KEYS.include?(key)
    return cast_template(value) if key == 'reengagement_template'
    return (value.blank? ? default : cast_integer(value)) if INTEGER_KEYS.include?(key)

    value
  end

  # Only true / "true" / "1" / 1 count: ActiveModel would read "no" as true.
  def self.strict_boolean(value)
    [true, 'true', '1', 1].include?(value)
  end

  def self.cast_integer(value)
    Integer(value.to_s, exception: false) || value
  end

  # nil or { 'name' => ..., 'language' => ... }; anything else is kept for the validator to reject.
  def self.cast_template(value)
    return if value.blank?
    return value unless value.respond_to?(:to_h) && !value.is_a?(Array)

    template = value.to_h.stringify_keys
    { 'name' => template['name'].to_s, 'language' => template['language'].to_s }
  end

  attr_reader :values

  def initialize(raw = nil)
    @values = self.class.normalize(raw)
  end

  def inactivity_enabled?
    values['inactivity_enabled'] == true
  end

  def reengagement_enabled?
    values['reengagement_enabled'] == true
  end

  def inactivity_after_minutes
    values['inactivity_after_minutes']
  end

  def max_nudges
    values['max_nudges']
  end

  def close_after_minutes
    values['close_after_minutes']
  end

  def reengagement_template
    values['reengagement_template']
  end

  def to_h
    values.deep_dup
  end
end
