class Captain::Copilot::DateFilter
  RELATIVE_RANGES = %w[today yesterday last_7_days last_30_days].freeze
  MAX_RANGE = 366.days
  RELATIVE_DAY_OFFSETS = {
    'today' => { after: 0, before: 0 },
    'yesterday' => { after: -1, before: -1 },
    'last_7_days' => { after: -6, before: -6 },
    'last_30_days' => { after: -29, before: -29 }
  }.freeze

  def initialize(timezone:, now: Time.current)
    @timezone = timezone.is_a?(ActiveSupport::TimeZone) ? timezone : ActiveSupport::TimeZone[timezone]
    @timezone ||= Time.zone
    @now = now.in_time_zone(@timezone)
  end

  def range(after_value, before_value)
    after_at, after_end = bound(after_value, :after) unless after_value.nil?
    before_at, before_end = bound(before_value, :before) unless before_value.nil?
    after_at ||= after_end
    before_at ||= before_end
    raise ArgumentError, 'date after is required when date before is provided' if before_at && after_at.nil?

    validate!(after_at, before_at)
    [after_at, before_at]
  end

  private

  def bound(value, side)
    raise ArgumentError, 'date filters must be strings' unless value.is_a?(String)

    return [nil, relative_range(value, side)] if RELATIVE_RANGES.include?(value)

    time = if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
             @timezone.parse(value).beginning_of_day
           else
             Time.iso8601(value).in_time_zone(@timezone)
           end
    [time, nil]
  rescue ArgumentError, TypeError
    raise ArgumentError, 'date filters must be ISO 8601 dates, timestamps, or today, yesterday, last_7_days, last_30_days'
  end

  def relative_range(value, side)
    offset = RELATIVE_DAY_OFFSETS.fetch(value).fetch(side)
    @now.beginning_of_day + offset.days
  end

  def validate!(after_at, before_at)
    range_end = before_at || @now
    raise ArgumentError, 'date after must be earlier than date before' if after_at && before_at && after_at >= before_at
    raise ArgumentError, "date range cannot exceed #{MAX_RANGE.to_i / 1.day.to_i} days" if after_at && range_end - after_at > MAX_RANGE
  end
end
