class Captain::Tools::SendEmailVerificationCodeTool < Captain::Tools::BasePublicTool
  description 'Send a one-time code to an email address the customer confirmed.'
  param :email, type: 'string', desc: 'Email address confirmed by the customer'

  def perform(tool_context, email:)
    conversation = find_conversation(tool_context.state)
    return failure_result(I18n.t('captain.email_verification.unavailable_conversation'), tool_context.state) unless conversation

    case Captain::EmailVerification.new(conversation).send_code(email)
    when :sent
      I18n.t('captain.email_verification.code_sent', email: email.to_s.strip.downcase,
                                                     minutes: Captain::EmailVerification::Code::TTL.in_minutes.to_i)
    when :already_verified then I18n.t('captain.email_verification.already_verified')
    when :unavailable then I18n.t('captain.email_verification.unavailable')
    when :rate_limited then I18n.t('captain.email_verification.rate_limited')
    else I18n.t('captain.email_verification.invalid_email')
    end
  end
end
