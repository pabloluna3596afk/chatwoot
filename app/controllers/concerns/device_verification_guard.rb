module DeviceVerificationGuard
  private

  # OSS has no device challenge; Enterprise supplies the interception.
  def device_verification_intercepted?(_user)
    false
  end

  def password_pre_auth_intercepted?
    user = find_user_for_authentication
    return false unless user

    if user.mfa_enabled?
      handle_mfa_required(user)
      return true
    end

    # A device challenge must precede enforced MFA enrollment. This prevents a
    # stolen password from reaching the enrollment flow from an unknown device.
    return true if device_verification_intercepted?(user)

    if user.mfa_enforcement_pending?
      handle_mfa_setup_required(user)
      return true
    end

    enforce_session_limit_for_password_login(user)
  end
end
