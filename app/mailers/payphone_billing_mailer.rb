class PayphoneBillingMailer < ApplicationMailer
  def notice
    @payment = params[:payment]
    @account = @payment.account
    @event = params[:event]
    @billing_url = "#{ENV.fetch('FRONTEND_URL')}/app/accounts/#{@account.id}/settings/billing"
    local_zone = Payphone::BillingLifecycle::ZONE
    period_end_date = @payment.period_end.in_time_zone(local_zone).to_date
    @days_remaining = period_end_date - Time.current.in_time_zone(local_zone).to_date
    recipients = @account.administrators.pluck(:email)
    mail(to: recipients, subject: I18n.t("payphone.billing_notice.#{@event}.subject", plan: @payment.plan.name))
  end
end
