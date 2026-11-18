# Account-wide daily limit for all Captain WhatsApp template sends.
class Captain::TemplateDailyCap
  DEFAULT_DAILY_CAP = 50

  def initialize(account, now: Time.current)
    @account = account
    @now = now
    @zone = Integrations::GoogleCalendar::Timezone.for(account)
  end

  def reserve!
    count = Redis::Alfred.incr(count_key)
    Redis::Alfred.expire(count_key, seconds_until_reset.to_i) if count == 1
    return true if count <= daily_cap

    release!
    notify_reached
    false
  end

  def release!
    Redis::Alfred.with { |connection| connection.decr(count_key) }
  end

  def used
    Redis::Alfred.get(count_key).to_i
  end

  def exhausted?
    used >= daily_cap
  end

  def notify_reached
    return unless Redis::Alfred.set(notice_key, '1', nx: true, ex: seconds_until_reset.to_i)

    AdministratorNotifications::AccountNotificationMailer.captain_template_cap_reached(@account, daily_cap).deliver_later
  end

  def daily_cap
    configured = @account.captain_template_daily_cap
    configured.nil? ? DEFAULT_DAILY_CAP : configured.to_i
  end

  private

  def count_key
    format(Redis::RedisKeys::CAPTAIN_TEMPLATE_DAILY_COUNT, account_id: @account.id, date: local_date)
  end

  def notice_key
    format(Redis::RedisKeys::CAPTAIN_TEMPLATE_DAILY_NOTICE, account_id: @account.id, date: local_date)
  end

  def local_date
    @local_date ||= @now.in_time_zone(@zone).to_date.to_s
  end

  def seconds_until_reset
    @now.in_time_zone(@zone).end_of_day - @now
  end
end
