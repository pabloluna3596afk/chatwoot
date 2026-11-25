# Value object behind the computed `message_time_window` automation condition.
#
# The stored value is one string: "HH:MM-HH:MM" with an optional "|day,day" suffix,
# for example "18:00-08:00" or "09:00-13:00|mon,tue,wed". The window starts at the
# first time (inclusive) and ends at the second (exclusive). When the end is
# earlier than the start the window crosses midnight. Days use the weekday on
# which the window starts, so "22:00-06:00|fri" also covers Saturday until 06:00.
class AutomationRules::TimeWindow
  DAYS = %w[sun mon tue wed thu fri sat].freeze
  TIME = '(?:[01]\d|2[0-3]):[0-5]\d'.freeze
  FORMAT = /\A(?<from>#{TIME})-(?<to>#{TIME})(?:\|(?<days>[a-z]{3}(?:,[a-z]{3})*))?\z/
  MINUTES_PER_DAY = 24 * 60

  attr_reader :start_minute, :end_minute, :wdays

  # Returns nil for anything that is not a well formed, non-empty window.
  def self.parse(value)
    match = FORMAT.match(value) if value.is_a?(String)
    return unless match

    wdays = weekdays(match[:days])
    start_minute = minutes_of(match[:from])
    end_minute = minutes_of(match[:to])
    return if wdays.nil? || start_minute == end_minute

    new(start_minute, end_minute, wdays)
  end

  # Whether `value` (a stored window) covers `time` read in `timezone`. Without a time it uses now.
  def self.matches?(value, time, timezone)
    window = parse(value)
    return false unless window

    zone = ActiveSupport::TimeZone[timezone.to_s] || ActiveSupport::TimeZone['UTC']
    window.cover?((time || Time.current).in_time_zone(zone))
  end

  # nil when a name is unknown or repeated.
  def self.weekdays(text)
    names = text.to_s.split(',')
    return if names.any? { |name| DAYS.exclude?(name) } || names.uniq.size != names.size

    names.map { |name| DAYS.index(name) }
  end

  def self.minutes_of(time)
    hours, minutes = time.split(':').map(&:to_i)
    (hours * 60) + minutes
  end

  def initialize(start_minute, end_minute, wdays)
    @start_minute = start_minute
    @end_minute = end_minute
    @wdays = wdays
  end

  def crosses_midnight?
    end_minute < start_minute
  end

  # `time` must already be expressed in the zone the window is read in.
  def cover?(time)
    minute = (time.hour * 60) + time.min
    start_wday = window_start_wday(time, minute)
    return false if start_wday.nil?

    wdays.empty? || wdays.include?(start_wday)
  end

  private

  # Weekday on which the window containing `time` started, or nil when `time` is outside the window.
  def window_start_wday(time, minute)
    return (minute >= start_minute && minute < end_minute ? time.wday : nil) unless crosses_midnight?
    return time.wday if minute >= start_minute
    return (time.wday - 1) % 7 if minute < end_minute

    nil
  end
end
