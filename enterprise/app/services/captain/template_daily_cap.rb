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
    format(Redis::RedisKeys::CAPTAIN_TEMPLATE_DAILY_COUNT, account_id: @account.id, date: period.first)
  end

  def notice_key
    format(Redis::RedisKeys::CAPTAIN_TEMPLATE_DAILY_NOTICE, account_id: @account.id, date: period.first)
  end

  # Capture the boundary once per account day; timezone edits cannot rotate an active counter.
  def period
    @period ||= begin
      key = format(Redis::RedisKeys::CAPTAIN_TEMPLATE_DAILY_PERIOD, account_id: @account.id)
      loop do
        stored = Redis::Alfred.get(key)
        if stored
          captured = JSON.parse(stored)
          break captured if @now.to_i < captured.last

          Redis::Alfred.delete_if_equals(key, stored)
        else
          reset_at = @now.in_time_zone(@zone).tomorrow.beginning_of_day
          captured = [@now.in_time_zone(@zone).to_date.to_s, reset_at.to_i]
          Redis::Alfred.set(key, captured.to_json, nx: true, ex: (reset_at - @now).ceil)
        end
      end
    end
  end

  def seconds_until_reset
    [period.last.to_i - @now.to_i, 1].max
  end
end
