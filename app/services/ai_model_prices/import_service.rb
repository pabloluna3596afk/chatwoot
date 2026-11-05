require 'csv'

class AiModelPrices::ImportService
  REQUIRED_HEADERS = %w[
    model effective_from active input_per_million cached_input_per_million output_per_million audio_per_minute
  ].freeze

  def initialize(file:)
    @file = file
  end

  def perform
    validate_headers
    CSV.foreach(@file, headers: true) { |row| import_row(row) }
  end

  private

  def validate_headers
    headers = CSV.open(@file, &:first)&.map(&:to_s)
    missing_headers = REQUIRED_HEADERS - headers.to_a
    return unless missing_headers.any?

    raise ArgumentError, "CSV is missing headers: #{missing_headers.join(', ')}"
  end

  def import_row(row)
    price = AiModelPrice.find_or_initialize_by(
      model: required_value(row, 'model'), effective_from: effective_from(row)
    )
    price.update!(price_attributes(row))
  end

  def required_value(row, key)
    row.fetch(key).presence || raise(ArgumentError, "#{key} cannot be blank")
  end

  def effective_from(row)
    Time.zone.parse(required_value(row, 'effective_from'))
  end

  def price_attributes(row)
    {
      active: parse_boolean(row.fetch('active')),
      input_per_million: parse_price(row.fetch('input_per_million')),
      cached_input_per_million: parse_price(row.fetch('cached_input_per_million')),
      output_per_million: parse_price(row.fetch('output_per_million')),
      audio_per_minute: parse_price(row.fetch('audio_per_minute'))
    }
  end

  def parse_boolean(value)
    return true if value == 'true'
    return false if value == 'false'

    raise ArgumentError, "active must be 'true' or 'false': #{value.inspect}"
  end

  def parse_price(value)
    return nil if value.blank?

    BigDecimal(value)
  rescue ArgumentError
    raise ArgumentError, "price must be a decimal or blank: #{value.inspect}"
  end
end
