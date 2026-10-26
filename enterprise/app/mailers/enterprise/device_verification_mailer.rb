class Enterprise::DeviceVerificationMailer < ApplicationMailer
  def verification_code(user, encrypted_code, meta = {})
    raise DeviceVerification::DeliveryError, 'SMTP is not configured' unless smtp_config_set_or_development?

    @user = user
    @code = DeviceVerification.decrypt_code(encrypted_code)
    @meta = meta || {}
    send_mail_with_liquid(to: user.email, subject: "Your #{brand_name} verification code")
  end

  def new_device(user, meta = {})
    return unless smtp_config_set_or_development?

    @user = user
    @meta = meta || {}
    send_mail_with_liquid(to: user.email, subject: "A new device signed in to your #{brand_name} account")
  end

  private

  def brand_name
    GlobalConfig.get_value('BRAND_NAME').presence || 'ChatHub'
  end

  def handle_smtp_exceptions(exception)
    Rails.logger.error "Device verification mail delivery failed: #{exception.message}"
    raise exception
  end

  def reset_password_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/auth/reset/password"
  end

  def liquid_locals
    super.merge(
      brand_name: brand_name,
      recipient_name: @user.name.presence || @user.email,
      code: @code,
      ip: @meta[:ip],
      browser_name: @meta[:browser_name],
      platform_name: @meta[:platform_name],
      reset_password_url: reset_password_url
    )
  end
end
