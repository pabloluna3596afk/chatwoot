class Payphone::OrderCreator
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  def call
    @account.with_lock { create_order }
  end

  private

  def create_order
    raise Payphone::ConfigurationError unless enabled?
    raise Payphone::AccountNotAllowed unless Payphone::AccountAccess.allowed?(@account)

    plan = purchasable_plan
    ensure_provider_and_plan_eligible!(plan)
    invoice = ActiveModel::Type::Boolean.new.cast(@params[:needs_invoice])
    pending = reusable_order(plan, invoice)
    return [pending, false] if pending
    raise Payphone::PendingOrderActive if active_pending_order?

    create_payment(plan, invoice)
  end

  def purchasable_plan
    Plan.active.where(is_public: true, coming_soon: false).find(@params.fetch(:plan_id))
  rescue ActiveRecord::RecordNotFound
    raise Payphone::UnavailablePlan
  end

  def ensure_provider_and_plan_eligible!(plan)
    raise Payphone::UnavailablePlan unless plan.price_monthly.positive?
    raise Payphone::StripeSubscriptionActive if stripe_subscription_active?

    latest_payment = @account.payphone_payments.where(status: 'approved').order(period_end: :desc).first
    raise Payphone::PaidPlanActive if latest_payment&.period_end&.future? && latest_payment.plan_id != plan.id
  end

  def reusable_order(plan, invoice)
    @account.payphone_payments.where(status: 'pending', plan: plan, needs_invoice: invoice)
            .where('created_at > ?', 15.minutes.ago).order(created_at: :desc).first
  end

  def active_pending_order?
    @account.payphone_payments.where(status: 'pending').exists?(['created_at > ?', 15.minutes.ago])
  end

  def create_payment(plan, invoice)
    breakdown = price_breakdown(plan, invoice)
    payment = @account.payphone_payments.create!(
      user: @user, plan: plan, client_transaction_id: SecureRandom.uuid,
      amount: breakdown.total_cents, base_cents: breakdown.base_cents,
      amount_without_tax: breakdown.amount_without_tax, amount_with_tax: breakdown.amount_with_tax,
      tax: breakdown.tax, tax_cents: breakdown.tax_cents, commission_cents: breakdown.commission_cents,
      needs_invoice: invoice, currency: 'USD', **invoice_attributes
    )
    [payment, true]
  end

  def price_breakdown(plan, invoice)
    Payphone::PriceCalculator.call(
      price: plan.price_monthly, needs_invoice: invoice,
      tax_rate: InstallationConfig.find_by(name: 'PAYPHONE_TAX_RATE')&.value || 15,
      commission_rate: InstallationConfig.find_by(name: 'PAYPHONE_CARD_COMMISSION_RATE')&.value || 5.75,
      commission_enabled: InstallationConfig.find_by(name: 'PAYPHONE_COMMISSION_ENABLED')&.value
    )
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(InstallationConfig.find_by(name: 'ENABLE_PAYPHONE')&.value)
  end

  def stripe_subscription_active?
    attributes = @account.custom_attributes
    return false if attributes['stripe_customer_id'].blank?

    attributes['subscription_status'].to_s == 'active' ||
      (attributes['subscription_ends_on'].present? && Time.zone.parse(attributes['subscription_ends_on']).future?)
  end

  def invoice_attributes
    return {} unless ActiveModel::Type::Boolean.new.cast(@params[:needs_invoice])

    @params.slice(:billing_tax_id_type, :billing_tax_id, :billing_name, :billing_email, :billing_phone,
                  :billing_address).to_h.symbolize_keys
  end
end
