# MockRedis cannot execute Lua. Opt these integration examples into the Redis service
# already provisioned by CI, with a fresh namespace so examples and workers stay isolated.
RSpec.configure do |config|
  config.before(:each, :real_redis) do
    @real_redis = Redis.new(Redis::Config.app)
    @real_redis_namespace = "spec:#{SecureRandom.hex(16)}"
    # Heartbeats and competing workers need independent connections: sharing a
    # single WATCH connection across threads changes the transaction semantics.
    @real_redis_pool = ConnectionPool.new(size: 5, timeout: 1) do
      Redis::Namespace.new(@real_redis_namespace, redis: Redis.new(Redis::Config.app), warning: true)
    end
    allow($alfred).to receive(:with) { |&block| @real_redis_pool.with(&block) } # rubocop:disable Style/GlobalVars
  end

  config.after(:each, :real_redis) do
    @real_redis.scan_each(match: "#{@real_redis_namespace}:*") { |key| @real_redis.del(key) }
  ensure
    @real_redis_pool.shutdown { |conn| conn.redis.close }
    @real_redis.close
  end
end
