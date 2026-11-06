# Read-only, unauthenticated plan catalog for the marketing website.
# Reuses Plan.catalog (active + public + not developer): whatever is public in
# the SuperAdmin is what is published. Freshness relies on HTTP caching only
# (short TTL + ETag over the payload), so there is nothing to invalidate.
class Public::Api::V1::PlansController < PublicController
  def index
    payload = Plans::PublicSerializer.payload
    expires_in 1.minute, public: true, 's-maxage': 5.minutes.to_i,
                         stale_while_revalidate: 1.day.to_i, stale_if_error: 1.day.to_i
    render json: payload if stale?(etag: payload, public: true)
  end
end
