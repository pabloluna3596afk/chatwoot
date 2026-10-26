class Captain::EmailVerification
  CODE_LENGTH = 6
  SEND_LIMIT = 5
  SEND_WINDOW = 1.hour
  VERIFIED_TTL = 1.hour
  EMAIL_VERIFIED_TTL = 3.hours
  EMAIL_PATTERN = /\A[a-z0-9._+-]+@[a-z0-9.-]+\z/

  pattr_initialize :conversation

  def self.encrypt_code(code)
    code_encryptor.encrypt_and_sign(code)
  end

  def self.decrypt_code(ciphertext)
    code_encryptor.decrypt_and_verify(ciphertext)
  end

  def self.code_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key('captain_email_verification_code', 32)
    ActiveSupport::MessageEncryptor.new(key)
  end
  private_class_method :code_encryptor

  def send_code(email)
    email = email.to_s.strip.downcase
    return :invalid_email unless EMAIL_PATTERN.match?(email) && ValidEmail2::Address.new(email).valid?
    return :already_verified if verified_email == email
    return :unavailable unless Captain::EmailVerificationMailer.deliverable?
    return :rate_limited unless send_allowed?(email)

    code = format("%0#{CODE_LENGTH}d", SecureRandom.random_number(10**CODE_LENGTH))
    pending_code.store(email, code)
    Captain::EmailVerificationMailer.with(account: conversation.account).verification_code(
      conversation.inbox, email, self.class.encrypt_code(code)
    ).deliver_later
    :sent
  end

  def verify(typed_code)
    pending_code.consume(typed_code) { |email| ::Redis::Alfred.setex(verified_key, email, verified_ttl) }
  end

  def verified_email
    ::Redis::Alfred.get(verified_key).presence
  end

  def attempts_left
    pending_code.attempts_left
  end

  def verified_ttl
    conversation.inbox.email? ? EMAIL_VERIFIED_TTL : VERIFIED_TTL
  end

  private

  def pending_code
    @pending_code ||= Captain::EmailVerification::Code.new(conversation)
  end

  def send_allowed?(email)
    email_key = format(::Redis::RedisKeys::CAPTAIN_EMAIL_VERIFICATION_EMAIL_SENDS, email_digest: Digest::SHA256.hexdigest(email))
    [sends_key, email_key].none? { |key| ::Redis::RateLimit.new(key, limit: SEND_LIMIT, window: SEND_WINDOW).exceeded? }
  end

  def verified_key
    format(::Redis::RedisKeys::CAPTAIN_EMAIL_VERIFICATION_VERIFIED, conversation_id: conversation.id)
  end

  def sends_key
    format(::Redis::RedisKeys::CAPTAIN_EMAIL_VERIFICATION_SENDS, contact_inbox_id: conversation.contact_inbox_id)
  end
end
