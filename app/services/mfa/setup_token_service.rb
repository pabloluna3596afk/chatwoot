class Mfa::SetupTokenService < BaseTokenService
  pattr_initialize [:user, :token]

  SETUP_TOKEN_EXPIRY = 10.minutes
  TOKEN_TYPE = 'mfa_setup'.freeze

  def generate_token
    @payload = { user_id: user.id, token_type: TOKEN_TYPE, pw: password_fingerprint(user),
                 exp: SETUP_TOKEN_EXPIRY.from_now.to_i }
    super
  end

  def verify_token
    decoded = decode_token
    return unless decoded.present? && decoded[:token_type] == TOKEN_TYPE

    found_user = User.find(decoded[:user_id])
    found_user if ActiveSupport::SecurityUtils.secure_compare(decoded[:pw].to_s, password_fingerprint(found_user))
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def password_fingerprint(record)
    Digest::SHA256.hexdigest(record.encrypted_password.to_s).first(16)
  end
end
