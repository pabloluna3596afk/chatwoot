class DeviceVerification::ChallengeService
  pattr_initialize [:user!, :request_meta]

  CODE_TTL = 10.minutes
  MAX_ATTEMPTS = 5
  ISSUANCE_LIMIT = 10
  ISSUANCE_WINDOW = 24.hours

  def issue!
    return nil unless issuance_allowed?

    jti = SecureRandom.hex(8)
    code = format('%06d', SecureRandom.random_number(10**6))
    ::Redis::Alfred.setex(self.class.code_key(user, jti), self.class.digest_for(code, jti), CODE_TTL)
    mail = Enterprise::DeviceVerificationMailer.verification_code(user, DeviceVerification.encrypt_code(code), request_meta || {})
    begin
      mail.deliver_now
    rescue StandardError => e
      raise DeviceVerification::DeliveryError, e.message
    end
    DeviceVerification::TokenService.new(user: user, jti: jti).generate_token
  rescue StandardError
    release_reservation(jti)
    raise
  end

  class << self
    def redeem(token:, code:)
      claims = DeviceVerification::TokenService.new(token: token).decode_claims
      return { error: :invalid_token } if claims.blank?

      user = User.find_by(id: claims[:user_id])
      return { error: :invalid_token } unless user
      return { error: :stale } if user.mfa_enabled? || !user.active_for_authentication?
      return { error: :stale } unless user.provider == 'email'
      return { error: :stale } unless claims[:stamp] == DeviceVerification::TokenService.stamp_for(user)

      consume(user, claims[:jti], code.to_s)
    end

    def code_key(user, jti)
      format(::Redis::RedisKeys::DEVICE_VERIFICATION_CODE, user_id: user.id, jti: jti)
    end

    def digest_for(code, jti)
      OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "#{jti}:#{code}")
    end

    private

    def consume(user, jti, code)
      attempts_key = format(::Redis::RedisKeys::DEVICE_VERIFICATION_ATTEMPTS, user_id: user.id, jti: jti)
      attempts = ::Redis::Alfred.incr(attempts_key)
      ::Redis::Alfred.expire(attempts_key, CODE_TTL.to_i) if attempts == 1
      return { error: :locked } if attempts > MAX_ATTEMPTS

      deleted = ::Redis::Alfred.delete_if_equals(code_key(user, jti), digest_for(code, jti))
      return { user: user } if deleted.is_a?(Array) && deleted.first.to_i == 1
      return { error: :expired } unless ::Redis::Alfred.exists?(code_key(user, jti))

      { error: :invalid_code }
    end
  end

  private

  def issuance_allowed?
    key = format(::Redis::RedisKeys::DEVICE_VERIFICATION_ISSUANCE, user_id: user.id)
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, ISSUANCE_WINDOW.to_i) if count == 1 || ::Redis::Alfred.ttl(key).to_i.negative?
    count <= ISSUANCE_LIMIT
  end

  def release_reservation(jti)
    ::Redis::Alfred.delete(self.class.code_key(user, jti)) if jti.present?
    issuance_key = format(::Redis::RedisKeys::DEVICE_VERIFICATION_ISSUANCE, user_id: user.id)
    ::Redis::Alfred.with { |conn| conn.decr(issuance_key) }
  end
end
