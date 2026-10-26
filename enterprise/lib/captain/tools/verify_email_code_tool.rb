class Captain::Tools::VerifyEmailCodeTool < Captain::Tools::BasePublicTool
  description 'Verify the one-time code entered by the customer.'
  param :code, type: 'string', desc: 'The one-time code entered by the customer'

  def perform(tool_context, code:)
    conversation = find_conversation(tool_context.state)
    return failure_result(I18n.t('captain.email_verification.unavailable_conversation'), tool_context.state) unless conversation

    verification = Captain::EmailVerification.new(conversation)
    result = verification.verify(code)
    case result
    when :verified
      tool_context.state[:verified_email] = verification.verified_email
      I18n.t('captain.email_verification.verified', email: verification.verified_email, count: verification.verified_ttl.in_hours.to_i)
    when :invalid_code
      key = verification.attempts_left.zero? ? 'captain.email_verification.no_attempts' : 'captain.email_verification.invalid_code'
      I18n.t(key, attempts: verification.attempts_left)
    when :locked then I18n.t('captain.email_verification.locked')
    else I18n.t('captain.email_verification.expired')
    end
  end
end
