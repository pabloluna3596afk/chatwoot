module GoogleCalendar::IntegrationHelper
  STATE_TTL = 10.minutes
  STATE_KEY = 'google_calendar:oauth:%<nonce>s'.freeze
  InvalidState = Class.new(StandardError)

  def generate_google_calendar_token(account_id)
    nonce = SecureRandom.hex(32)
    session[:google_calendar_oauth_session] ||= SecureRandom.hex(32)
    payload = {
      sub: account_id, user_id: current_user.id, jti: nonce,
      session: Digest::SHA256.hexdigest(session[:google_calendar_oauth_session]),
      iat: Time.current.to_i, exp: STATE_TTL.from_now.to_i
    }
    token = JWT.encode(payload, google_calendar_client_secret, 'HS256')
    Redis::Alfred.set(format(STATE_KEY, nonce: nonce), Digest::SHA256.hexdigest(token), ex: STATE_TTL.to_i)
    token
  end

  def verify_google_calendar_token(token)
    raise InvalidState if token.blank?

    payload = JWT.decode(token, google_calendar_client_secret, true, { algorithm: 'HS256', verify_expiration: true }).first
    stored = consume_google_calendar_state(payload.fetch('jti'))
    raise InvalidState unless stored == Digest::SHA256.hexdigest(token)
    raise InvalidState unless payload['session'] == Digest::SHA256.hexdigest(session[:google_calendar_oauth_session].to_s)
    raise InvalidState if current_user && current_user.id != payload['user_id']

    payload
  rescue JWT::DecodeError, KeyError
    raise InvalidState
  end

  private

  # redis-namespace 1.x does not namespace GETDEL. MULTI/EXEC keeps both
  # operations atomic while applying the namespace to GET and DEL correctly.
  def consume_google_calendar_state(nonce)
    key = format(STATE_KEY, nonce: nonce)
    Redis::Alfred.with do |conn|
      conn.multi do |transaction|
        transaction.get(key)
        transaction.del(key)
      end.first
    end
  end

  def google_calendar_client_secret
    @google_calendar_client_secret ||= GlobalConfigService.load('GOOGLE_CALENDAR_CLIENT_SECRET', nil)
  end
end
