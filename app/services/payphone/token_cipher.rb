class Payphone::TokenCipher
  PREFIX = 'payphone:v1:'.freeze

  def self.encrypt(token)
    return token if token.blank? || encrypted?(token)

    PREFIX + encryptor.encrypt_and_sign(token)
  end

  def self.decrypt(token)
    return token unless encrypted?(token)

    encryptor.decrypt_and_verify(token.delete_prefix(PREFIX))
  end

  def self.encrypted?(token)
    token.to_s.start_with?(PREFIX)
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key('payphone/installation-token/v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
  private_class_method :encryptor
end
