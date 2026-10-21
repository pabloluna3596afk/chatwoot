# Liquid date helpers for automation CA updates and message templates.
#
# Relative dates (CRM): prefer filters in config/initializers/liquid_filters.rb —
#   {{ date.today }}                 → today (ISO YYYY-MM-DD via to_s)
#   {{ date.today | plus_days: 7 }}  → today + N
#   {{ date.today | minus_days: 30 }} → today - N
# ActionService renders these through Variables::ValueNormalizer before parsing date CAs.
class DateDrop < Liquid::Drop
  def initialize(timezone: Time.zone)
    @timezone = timezone
    super()
  end

  def today
    current_time.to_date
  end

  def now
    current_time
  end

  def tomorrow
    (current_time + 1.day).to_date
  end

  def yesterday
    (current_time - 1.day).to_date
  end

  # Bare {{ date.days_from_now }} → today. Liquid cannot pass Ruby args here;
  # use {{ date.today | plus_days: N }} instead (see class comment).
  def days_from_now
    current_time.to_date
  end

  # Bare {{ date.days_ago }} → today. Use {{ date.today | minus_days: N }} instead.
  def days_ago
    current_time.to_date
  end

  # Returns the current year/month/day as integers
  def current_year
    current_time.year
  end

  def current_month
    current_time.month
  end

  def current_day
    current_time.day
  end

  private

  def current_time
    Time.current.in_time_zone(@timezone)
  end
end
