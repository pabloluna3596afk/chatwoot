require 'rails_helper'

RSpec.describe AiModelPrice do
  it 'seeds the gpt-6-luna rates for standard input, cached input, and output' do
    described_class.seed_defaults!

    price = described_class.find_by!(model: 'gpt-6-luna')
    expect(price).to have_attributes(
      input_per_million: BigDecimal('0.10'),
      cached_input_per_million: BigDecimal('0.01'),
      output_per_million: BigDecimal('0.50')
    )
  end
end
