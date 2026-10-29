class PayphoneReceiptMailer < ApplicationMailer
  def receipt
    @payment = params[:payment]
    @account = @payment.account
    mail(to: @payment.user.email, subject: I18n.t('payphone.receipt.subject', plan: @payment.plan.name))
  end
end
