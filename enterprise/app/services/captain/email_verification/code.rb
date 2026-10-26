class Captain::EmailVerification::Code
  TTL = 30.minutes
  MAX_ATTEMPTS = 5

  pattr_initialize :conversation

  def store(email, code)
    ::Redis::Alfred.with do |conn|
      conn.multi do |transaction|
        transaction.setex(code_key, TTL.to_i, stored_value(email, code))
        transaction.del(attempts_key)
      end
    end
  end

  def consume(typed_code)
    stored = ::Redis::Alfred.get(code_key)
    return :expired if stored.blank?
    return :locked if attempts.exceeded?

    email = JSON.parse(stored)['email']
    return :invalid_code unless ::Redis::Alfred.delete_if_equals(code_key, stored_value(email, typed_code.to_s.strip)) == [1]

    yield email
    :verified
  end

  def attempts_left
    attempts.remaining
  end

  private

  def stored_value(email, code)
    digest = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "#{conversation.id}:#{email}:#{code}")
    { email: email, digest: digest }.to_json
  end

  def attempts
    ::Redis::RateLimit.new(attempts_key, limit: MAX_ATTEMPTS, window: TTL)
  end

  def code_key
    format(::Redis::RedisKeys::CAPTAIN_EMAIL_VERIFICATION_CODE, conversation_id: conversation.id)
  end

  def attempts_key
    format(::Redis::RedisKeys::CAPTAIN_EMAIL_VERIFICATION_ATTEMPTS, conversation_id: conversation.id)
  end
end
