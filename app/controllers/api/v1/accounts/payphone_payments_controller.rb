class Api::V1::Accounts::PayphonePaymentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :validate_invoice_flag, only: %i[create quote]

  def index
    latest_approved = @current_account.payphone_payments.where(status: 'approved').order(period_end: :desc).first
    render json: {
      enabled: ActiveModel::Type::Boolean.new.cast(InstallationConfig.find_by(name: 'ENABLE_PAYPHONE')&.value),
      renewal_state: renewal_state(latest_approved), period_end: latest_approved&.period_end,
      grace_end: grace_end(latest_approved),
      payments: @current_account.payphone_payments.includes(:plan).order(created_at: :desc).limit(50).map { |payment| serialize(payment) }
    }
  end

  def create
    payment, created = Payphone::OrderCreator.new(account: @current_account, user: current_user, params: payment_params).call
    render json: serialize(payment).merge(box: box_config(payment), created: created), status: created ? :created : :ok
  rescue Payphone::ConfigurationError
    render json: { error: I18n.t('payphone.errors.disabled') }, status: :unprocessable_entity
  rescue Payphone::UnavailablePlan, ActiveRecord::RecordNotFound
    render json: { error: I18n.t('payphone.errors.plan_unavailable') }, status: :unprocessable_entity
  rescue Payphone::StripeSubscriptionActive
    render json: { error: I18n.t('payphone.errors.stripe_active') }, status: :conflict
  rescue Payphone::PaidPlanActive
    render json: { error: I18n.t('payphone.errors.paid_plan_active') }, status: :conflict
  rescue Payphone::PendingOrderActive
    render json: { error: I18n.t('payphone.errors.pending_order_active') }, status: :conflict
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def quote
    plan = Plan.active.where(is_public: true, coming_soon: false).find(params.require(:plan_id))
    raise Payphone::UnavailablePlan unless plan.price_monthly.positive?

    breakdown = quote_breakdown(plan)
    render json: { plan: plan.name, base_cents: breakdown.base_cents, tax_cents: breakdown.tax_cents,
                   commission_cents: breakdown.commission_cents, amount: breakdown.total_cents, currency: 'USD' }
  rescue Payphone::UnavailablePlan, ActiveRecord::RecordNotFound
    render json: { error: I18n.t('payphone.errors.plan_unavailable') }, status: :unprocessable_entity
  end

  def preview_confirm
    return head :not_found unless ENV['PAYPHONE_PREVIEW_FAKE'] == '1'
    return head :unprocessable_entity unless %w[approved cancelled pending].include?(params[:status])

    payment = @current_account.payphone_payments.find(params[:id])
    status_code = { 'approved' => 3, 'cancelled' => 2, 'pending' => 1 }.fetch(params[:status])
    fake_client = Payphone::FakeClient.new(payment: payment, status_code: status_code)
    Payphone::ConfirmPayment.new(payment: payment, transaction_id: (payment.id + 10_000).to_s,
                                 client_transaction_id: payment.client_transaction_id, client: fake_client).call
    render json: serialize(payment)
  rescue Payphone::ConfirmationError
    render json: { status: 'verifying' }, status: :accepted
  end

  private

  def check_admin_authorization?
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('errors.access_denied') }, status: :forbidden
  end

  def account_accessible_for_user?(account)
    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    render json: { error: I18n.t('errors.account.not_authorized') }, status: :not_found unless @current_account_user
  end

  def renewal_state(payment)
    return unless payment
    return 'expired' if Time.current >= payment.period_end + Payphone::BillingLifecycle::GRACE_DAYS.days
    return 'grace' if Time.current >= payment.period_end

    due_date = payment.period_end.in_time_zone(Payphone::BillingLifecycle::ZONE).to_date
    'due_soon' if due_date <= Time.current.in_time_zone(Payphone::BillingLifecycle::ZONE).to_date + 7.days
  end

  def grace_end(payment)
    return unless payment

    payment.period_end + Payphone::BillingLifecycle::GRACE_DAYS.days
  end

  def payment_params
    params.permit(:plan_id, :needs_invoice, :billing_tax_id_type, :billing_tax_id, :billing_name,
                  :billing_email, :billing_phone, :billing_address)
  end

  def quote_breakdown(plan)
    Payphone::PriceCalculator.call(
      price: plan.price_monthly, needs_invoice: ActiveModel::Type::Boolean.new.cast(params[:needs_invoice]),
      tax_rate: InstallationConfig.find_by(name: 'PAYPHONE_TAX_RATE')&.value || 15,
      commission_rate: InstallationConfig.find_by(name: 'PAYPHONE_CARD_COMMISSION_RATE')&.value || 5.75,
      commission_enabled: InstallationConfig.find_by(name: 'PAYPHONE_COMMISSION_ENABLED')&.value
    )
  end

  def validate_invoice_flag
    return if params[:needs_invoice].nil? || [true, false].include?(params[:needs_invoice])

    render json: { error: I18n.t('payphone.errors.invalid_request') }, status: :unprocessable_entity
  end

  def box_config(payment)
    preview = ENV['PAYPHONE_PREVIEW_FAKE'] == '1'
    {
      storeId: preview ? 'preview-store' : InstallationConfig.find_by(name: 'PAYPHONE_STORE_ID')&.value,
      token: preview ? 'preview-token' : box_token,
      clientTransactionId: payment.client_transaction_id,
      amount: payment.amount, amountWithoutTax: payment.amount_without_tax,
      amountWithTax: payment.amount_with_tax, tax: payment.tax, service: payment.commission_cents,
      currency: payment.currency, reference: "Plan #{payment.plan.name}",
      preview: preview
    }
  end

  def box_token
    InstallationConfig.find_by(name: 'PAYPHONE_BOX_TOKEN')&.value.presence ||
      InstallationConfig.find_by(name: 'PAYPHONE_TOKEN')&.value
  end

  def serialize(payment)
    {
      id: payment.id, plan: payment.plan.name, amount: payment.amount, currency: payment.currency,
      status: payment.status, client_transaction_id: payment.client_transaction_id,
      paid_at: payment.paid_at, period_start: payment.period_start, period_end: payment.period_end,
      created_at: payment.created_at
    }
  end
end
