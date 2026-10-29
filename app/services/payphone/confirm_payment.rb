class Payphone::ConfirmPayment
  def initialize(payment:, transaction_id:, client_transaction_id:, client: Payphone::Client.new)
    @payment = payment
    @transaction_id = transaction_id.to_s
    @client_transaction_id = client_transaction_id
    @client = client
  end

  def call
    return @payment if @payment.approved?
    raise Payphone::ConfirmationError unless @payment.pending? && @payment.client_transaction_id == @client_transaction_id
    raise Payphone::ConfirmationError if @payment.created_at <= 15.minutes.ago

    response = @client.confirm(transaction_id: @transaction_id, client_transaction_id: @client_transaction_id)
    begin
      verify!(response)
    rescue Payphone::IncongruentConfirmation
      @payment.transition_to!('failed', attributes: { raw_response: safe_response(response) })
      raise
    end
    complete_payment(response)
  end

  private

  def complete_payment(response)
    newly_approved = false
    @payment.with_lock do
      return @payment if @payment.approved?
      raise Payphone::ConfirmationError unless @payment.pending?

      @payment.transition_to!(payment_status(response), attributes: payment_attributes(response))
      newly_approved = @payment.approved?
    end
    send_receipt if newly_approved
    @payment
  end

  def payment_status(response)
    return 'approved' if response['statusCode'] == 3
    return 'cancelled' if response['statusCode'] == 2

    'failed'
  end

  def payment_attributes(response)
    attributes = { raw_response: safe_response(response) }
    attributes[:payphone_transaction_id] = response['transactionId'].to_s if response['transactionId'].present?
    attributes[:authorization_code] = response['authorizationCode'] if response['authorizationCode'].present?
    return attributes unless payment_status(response) == 'approved'

    activate_period!
    attributes.merge(paid_at: Time.current, confirmed_at: Time.current,
                     period_start: @period_start, period_end: @period_end)
  end

  def send_receipt
    PayphoneReceiptMailer.with(account: @payment.account, payment: @payment).receipt.deliver_later
  end

  def safe_response(response)
    response.is_a?(Hash) ? response.slice(*PayphonePayment::RAW_RESPONSE_KEYS) : {}
  end

  def verify!(response)
    raise Payphone::IncongruentConfirmation unless valid_confirmation?(response)
  end

  def valid_confirmation?(response)
    return false unless response.is_a?(Hash)
    return false unless response['clientTransactionId'] == @payment.client_transaction_id
    return false unless response['transactionId'].to_s == @transaction_id
    return false unless response['amount'] == @payment.amount && response['currency'] == @payment.currency
    return false unless response['statusCode'].is_a?(Integer)

    PayphonePayment.where(payphone_transaction_id: @transaction_id).where.not(id: @payment.id).none?
  end

  def activate_period!
    @payment.account.with_lock do
      account = @payment.account
      previous = active_paid_period(account)
      ensure_same_plan_or_expired!(previous)

      @period_start = previous ? [Time.current, previous.period_end].max : Time.current
      @period_end = @period_start + 30.days
      plan_changed = account.plan_id != @payment.plan_id
      account.update!(plan_id: @payment.plan_id, plan_started_at: @period_start)
      account.restart_usage_period_for_billing!(anchor: @period_start) if previous.nil? && !plan_changed
    end
  end

  def active_paid_period(account)
    account.payphone_payments.where(status: 'approved').where.not(id: @payment.id).where('period_end > ?', Time.current)
           .order(period_end: :desc).first
  end

  def ensure_same_plan_or_expired!(previous)
    raise Payphone::PaidPlanActive if previous && previous.plan_id != @payment.plan_id
  end
end
