class Reports::PanelDateRange
  MAX_RANGE_DAYS = 366

  def self.timezone(account = nil)
    ActiveSupport::TimeZone[account&.reporting_timezone.presence || Time.zone.name]
  end

  def self.resolve(preset, custom_since: nil, custom_until: nil, account: nil)
    zone = timezone(account)
    return validate(custom_since, custom_until, account: account) if preset.to_s == 'custom'

    today = zone.today
    first_day, last_day = case preset.to_s
                          when 'today' then [today, today]
                          when 'yesterday' then [today - 1, today - 1]
                          when 'last_30_days' then [today - 29, today]
                          else [today - 6, today]
                          end
    [zone.local(first_day.year, first_day.month, first_day.day),
     zone.local(last_day.year, last_day.month, last_day.day).end_of_day]
  end

  def self.validate(since_value, until_value, account: nil)
    values = [since_value, until_value]
    raise CustomExceptions::InvalidReportDateRange, 'since and until must be integers' unless values.all? { |value| integer_timestamp?(value) }

    since_time, until_time = values.map { |value| timezone(account).at(value.to_i) }
    # Unix until includes its final second, as it does in the report builders.
    until_time = until_time.change(usec: 999_999)
    if since_time > until_time || (until_time.to_date - since_time.to_date).to_i >= MAX_RANGE_DAYS
      raise CustomExceptions::InvalidReportDateRange, 'since must be <= until and the range must not exceed 366 calendar days'
    end

    [since_time, until_time]
  end

  def self.integer_timestamp?(value)
    value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+\z/))
  end
  private_class_method :integer_timestamp?
end
