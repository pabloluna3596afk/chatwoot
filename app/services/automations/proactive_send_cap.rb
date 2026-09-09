# frozen_string_literal: true

# Account-wide throttle for autonomous outbound sends triggered by contact-based
# automation rules (birthdays, anniversaries, win-backs). These rules act without
# a human in the loop, so a misconfigured audience (or a large attribute-category
# import) must not be able to blast the entire contact base in one scheduler run.
class Automations::ProactiveSendCap
  DEFAULT_DAILY_CAP = 200

  def initialize(account)
    @account = account
  end

  def within_cap?
    current_count < daily_cap
  end

  def increment!
    new_count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, 1.day.to_i) if new_count == 1
  end

  private

  def daily_cap
    configured = @account.settings&.dig('proactive_daily_send_cap')
    configured.present? ? configured.to_i : DEFAULT_DAILY_CAP
  end

  def current_count
    ::Redis::Alfred.get(key).to_i
  end

  def key
    format(::Redis::RedisKeys::PROACTIVE_SEND_DAILY_COUNT, account_id: @account.id, date: Time.zone.today.to_s)
  end
end
