class Payphone::PriceCalculator
  Breakdown = Struct.new(
    :base_cents, :tax_cents, :commission_cents, :total_cents,
    :amount_without_tax, :amount_with_tax, :tax, :service,
    keyword_init: true
  )

  def self.call(price:, needs_invoice:, tax_rate: 15, commission_rate: 5.75, commission_enabled: true)
    new(
      price: price,
      needs_invoice: needs_invoice,
      tax_rate: tax_rate,
      commission_rate: commission_rate,
      commission_enabled: commission_enabled
    ).call
  end

  def initialize(price:, needs_invoice:, tax_rate:, commission_rate:, commission_enabled:)
    @price = price
    @needs_invoice = needs_invoice
    @tax_rate = BigDecimal(tax_rate.to_s)
    @commission_rate = BigDecimal(commission_rate.to_s)
    @commission_enabled = commission_enabled
  end

  def call
    base_cents = cents(@price)
    validate_inputs(base_cents)

    tax_cents = @needs_invoice ? percentage(base_cents, @tax_rate) : 0
    commission_cents = @commission_enabled ? percentage(base_cents + tax_cents, @commission_rate) : 0
    total_cents = base_cents + tax_cents + commission_cents

    Breakdown.new(
      base_cents: base_cents,
      tax_cents: tax_cents,
      commission_cents: commission_cents,
      total_cents: total_cents,
      amount_without_tax: @needs_invoice ? 0 : base_cents,
      amount_with_tax: @needs_invoice ? base_cents : 0,
      tax: tax_cents,
      service: commission_cents
    )
  end

  private

  def cents(amount)
    round_cents(BigDecimal(amount.to_s) * 100)
  end

  def validate_inputs(base_cents)
    raise ArgumentError, 'plan price must be nonnegative' if base_cents.negative?
    raise ArgumentError, 'tax rate must be between 0 and 100' unless @tax_rate.between?(0, 100)
    raise ArgumentError, 'commission rate must be between 0 and 100' unless @commission_rate.between?(0, 100)
  end

  def percentage(amount, rate)
    round_cents(BigDecimal(amount.to_s) * rate / 100)
  end

  def round_cents(amount)
    amount.round(0, BigDecimal::ROUND_HALF_UP).to_i
  end
end
