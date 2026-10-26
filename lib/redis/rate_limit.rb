# Counts hits on a fixed window that starts with the first hit.
class Redis::RateLimit
  pattr_initialize :key, [:limit!, :window!]

  def exceeded?
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, window.to_i) if count == 1 || Redis::Alfred.ttl(key).to_i.negative?
    count > limit
  end

  def remaining
    [limit - Redis::Alfred.get(key).to_i, 0].max
  end
end
