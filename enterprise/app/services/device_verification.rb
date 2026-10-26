module DeviceVerification
  class DeliveryError < StandardError; end

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('DEVICE_VERIFICATION_ENABLED', false))
  end

  def self.exempt?(user)
    GlobalConfigService.load('DEVICE_VERIFICATION_EXEMPT_EMAILS', '').to_s
                       .split("\n").map { |email| email.strip.downcase }.include?(user.email.downcase)
  end

  def self.reset_issuance_budget(user_id)
    ::Redis::Alfred.delete(format(::Redis::RedisKeys::DEVICE_VERIFICATION_ISSUANCE, user_id: user_id))
  end

  def self.encrypt_code(code)
    code_encryptor.encrypt_and_sign(code)
  end

  def self.decrypt_code(ciphertext)
    code_encryptor.decrypt_and_verify(ciphertext)
  end

  def self.code_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
                                     .generate_key('device_verification_code', 32)
    ActiveSupport::MessageEncryptor.new(key)
  end
  private_class_method :code_encryptor
end
