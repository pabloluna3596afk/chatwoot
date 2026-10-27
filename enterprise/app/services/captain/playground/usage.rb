class Captain::Playground::Usage
  RATE_LIMIT = 6

  class LimitExceeded < StandardError
    attr_reader :code, :status, :retry_after

    def initialize(code, status: :too_many_requests, retry_after: nil)
      @code = code
      @status = status
      @retry_after = retry_after
      super(I18n.t("captain.playground.#{code}"))
    end
  end

  # Redis performs the check, increment and expiry together, including across Rails workers.
  DAILY_SCRIPT = <<~LUA.freeze
    local count = redis.call('INCR', KEYS[1])
    redis.call('EXPIREAT', KEYS[1], ARGV[1])
    return count
  LUA
  RATE_SCRIPT = <<~LUA.freeze
    redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1] - 60)
    if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) then
      local first = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
      return math.max(1, math.ceil(tonumber(first[2]) + 60 - ARGV[1]))
    end
    redis.call('ZADD', KEYS[1], ARGV[1], ARGV[3])
    redis.call('EXPIRE', KEYS[1], 60)
    return 0
  LUA

  def initialize(account:)
    @account = account
  end

  def perform(&)
    check_rate!
    # All playground entry points share this lock, including different assistants/tabs.
    @account.with_lock do
      perform_locked(&)
    end
  end

  def remaining
    { test_usage: test_usage }
  end

  def test_usage
    return if @account.plan.nil? || @account.own_ai_key_configured?

    free = @account.plan.price_monthly.zero? || @account.plan.is_default_trial?
    total = daily_test_limit(free)
    used = Redis::Alfred.get(daily_key).to_i
    remaining = total.nil? ? ChatwootApp.max_limit : [total - used, 0].max
    { plan_kind: free ? 'free' : 'paid', daily_total: total, daily_used: used,
      daily_remaining: remaining, uses_plan_pool: remaining.zero?, plan_remaining: plan_remaining }
  end

  private

  def daily_test_limit(free)
    return if @account.plan.unlimited_limit?(:captain_daily_tests)

    free ? 0 : @account.plan_limit(:captain_daily_tests)
  end

  def perform_locked
    snapshot = test_usage
    enforce_plan_limit!(snapshot)
    response = yield
    record_usage(snapshot, response)
    response.merge(remaining)
  end

  def enforce_plan_limit!(snapshot)
    return unless snapshot && snapshot[:uses_plan_pool] && plan_remaining <= 0

    raise LimitExceeded.new('responses_limit_reached', status: :unprocessable_entity)
  end

  def record_usage(snapshot, response)
    return unless snapshot && response[:error].blank? && response[:response].present?

    snapshot[:uses_plan_pool] ? @account.increment_response_usage : count_daily!
  end

  def plan_remaining = @account.usage_limits[:captain][:responses][:current_available]

  def daily_key
    @daily_key ||= begin
      @day = Time.current.in_time_zone(@account.reporting_timezone.presence || 'UTC')
      "captain:playground:daily:#{@account.id}:#{@day.to_date}"
    end
  end

  def count_daily!
    key = daily_key
    Redis::Alfred.with do |redis|
      redis.eval(DAILY_SCRIPT, keys: [key], argv: [@day.tomorrow.beginning_of_day.to_i])
    end
  end

  def check_rate!
    retry_after = Redis::Alfred.with do |redis|
      redis.eval(RATE_SCRIPT, keys: ["captain:playground:rate:#{@account.id}"],
                              argv: [Time.current.to_f, RATE_LIMIT, SecureRandom.uuid])
    end
    raise LimitExceeded.new('playground_rate_limit', retry_after: retry_after) if retry_after.positive?
  end
end
