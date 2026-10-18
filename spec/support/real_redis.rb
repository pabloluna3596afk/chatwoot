# MockRedis cannot execute Lua. Opt these integration examples into the Redis service
# already provisioned by CI, with a fresh namespace so examples and workers stay isolated.
RSpec.configure do |config|
  config.before(:each, :real_redis) do
    @real_redis = Redis.new(Redis::Config.app)
    @real_redis_namespace = "spec:#{SecureRandom.hex(16)}"
    redis = Redis::Namespace.new(@real_redis_namespace, redis: @real_redis, warning: true)
    allow($alfred).to receive(:with).and_yield(redis) # rubocop:disable Style/GlobalVars
  end

  config.after(:each, :real_redis) do
    @real_redis.scan_each(match: "#{@real_redis_namespace}:*") { |key| @real_redis.del(key) }
  ensure
    @real_redis.close
  end
end
