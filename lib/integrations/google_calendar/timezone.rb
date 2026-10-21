# One account zone for Google, dashboard, Captain and reminders. Local inputs
# reject DST gaps and choose the earlier instant in a fold; explicit offsets
# identify an instant and may select either occurrence.
module Integrations::GoogleCalendar::Timezone
  def self.for(account)
    Time.find_zone!(account.reporting_timezone.presence || Integrations::GoogleCalendar::Client::TIMEZONE)
  end

  def self.parse(value, zone:)
    return Time.iso8601(value).in_time_zone(zone) if value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/i)

    civil = DateTime.iso8601(value)
    local = Time.utc(civil.year, civil.month, civil.day, civil.hour, civil.minute, civil.second)
    periods = zone.tzinfo.periods_for_local(local)
    raise ArgumentError, 'Nonexistent local appointment time' if periods.empty?

    zone.at(local.to_r - periods.map(&:utc_total_offset).max)
  end
end
