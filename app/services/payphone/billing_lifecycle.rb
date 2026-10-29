class Payphone::BillingLifecycle
  ZONE = 'America/Guayaquil'.freeze
  REMINDER_DAYS = [7, 3, 1].freeze
  GRACE_DAYS = 3

  def self.call(now: Time.current)
    new(now: now).call
  end

  def initialize(now:)
    @now = now
  end

  def call
    Time.use_zone(ZONE) do
      PayphonePayment.where(status: 'approved').where.not(period_end: nil).find_each do |payment|
        process_payment(payment)
      end
    end
  end

  private

  def process_payment(payment)
    payment.with_lock do
      return unless payment.approved? && payment.period_end.present?

      REMINDER_DAYS.each do |days|
        renewal_date = payment.period_end.in_time_zone(ZONE).to_date - days.days
        record_event(payment, "renewal_reminder_#{days}") if local_today == renewal_date
      end
      record_event(payment, 'grace_started') if @now >= payment.period_end
      downgrade_account(payment) if @now >= payment.period_end + GRACE_DAYS.days
    end
  end

  def record_event(payment, event)
    return if payment.status_history.any? { |entry| entry['event'] == event }

    payment.status_history = payment.status_history + [{ 'event' => event, 'at' => @now.iso8601 }]
    payment.save!
    deliver_notice(payment, event)
  end

  def downgrade_account(payment)
    event = 'downgraded_to_free'
    return if payment.status_history.any? { |entry| entry['event'] == event }

    account = payment.account
    account.with_lock do
      current_period = account.payphone_payments.where(status: 'approved', plan_id: account.plan_id)
                              .where('period_end > ?', @now).order(period_end: :desc).first
      return if current_period

      free_plan = Plan.active.find_by!(slug: 'gratis')
      account.update!(plan: free_plan, plan_started_at: @now)
      payment.status_history = payment.status_history + [{ 'event' => event, 'at' => @now.iso8601 }]
      payment.save!
      deliver_notice(payment, event)
    end
  end

  def local_today
    @now.in_time_zone(ZONE).to_date
  end

  def deliver_notice(payment, event)
    return if payment.account.administrators.none?

    PayphoneBillingMailer.with(payment: payment, event: event).notice.deliver_later
  end
end
