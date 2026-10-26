module MfaEnforcementGuard
  extend ActiveSupport::Concern

  private

  def check_user_mfa_enforcement
    user = Current.user
    return unless Current.account&.enforce_mfa? && user.is_a?(User)
    return if user.mfa_enabled? || %w[google_oauth2 saml].include?(user.provider)

    render json: { error: I18n.t('errors.mfa.enrollment_required'), error_code: 'mfa_enrollment_required' }, status: :forbidden
  end
end
