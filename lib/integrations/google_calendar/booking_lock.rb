class Integrations::GoogleCalendar::BookingLock
  # ponytail: one mutex per Google calendar for the length of a create/update.
  # Ceiling: non-overlapping bookings on the same calendar wait on each other.
  # Upgrade: lock rounded interval keys instead of the whole calendar.
  TTL = 20
  HEARTBEAT_INTERVAL = TTL / 4.0

  class Lost < StandardError; end

  def initialize(account_id:, calendar_id:)
    @key = format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: account_id, calendar_id: calendar_id)
    @token = SecureRandom.uuid
    @acquired = false
    @mutex = Mutex.new
    @wake = ConditionVariable.new
  end

  def acquire
    @acquired = Redis::Alfred.set(@key, @token, nx: true, ex: TTL)
    @heartbeat = Thread.new { heartbeat } if @acquired
    @acquired
  end

  # Check and renew atomically before starting another write. A failed heartbeat
  # permanently invalidates this lease, even if Redis subsequently recovers.
  def assert_owned!
    @mutex.synchronize do
      raise Lost if @lost || !@acquired || !renew
    end
  rescue StandardError
    @mutex.synchronize { @lost = true }
    raise Lost
  end

  def release
    return unless @acquired

    @mutex.synchronize do
      @stopped = true
      @wake.broadcast
    end
    @heartbeat.join
    Redis::Alfred.delete_if_equals(@key, @token)
    @acquired = false
  end

  private

  def renew
    Redis::Alfred.with do |conn|
      conn.watch(@key) do
        if conn.get(@key) == @token
          conn.multi { |transaction| transaction.expire(@key, TTL) }
        else
          conn.unwatch
          false
        end
      end
    end
  end

  def heartbeat
    @mutex.synchronize do
      until @stopped
        @wake.wait(@mutex, HEARTBEAT_INTERVAL)
        break if @stopped

        unless renew
          @lost = true
          break
        end
      end
    end
  rescue StandardError
    @mutex.synchronize { @lost = true }
  end
end
