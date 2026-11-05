require 'rails_helper'
require 'tempfile'

RSpec.describe AiModelPrices::ImportService do
  it 'imports and updates prices idempotently from a complete CSV row' do
    csv = Tempfile.new(['ai-model-prices', '.csv'])
    csv.write(<<~CSV)
      model,effective_from,active,input_per_million,cached_input_per_million,output_per_million,audio_per_minute
      fake-audio-model,2026-11-01,true,0.01234567,0.00234567,0.03234567,0.12345678
    CSV
    csv.close
    2.times do
      described_class.new(file: csv.path).perform
    end

    expect(AiModelPrice.where(model: 'fake-audio-model').count).to eq(1)
    expect(AiModelPrice.find_by!(model: 'fake-audio-model')).to have_attributes(
      active: true, input_per_million: BigDecimal('0.01234567'), audio_per_minute: BigDecimal('0.12345678')
    )
  ensure
    csv&.unlink
  end

  it 'rejects missing required headers' do
    csv = Tempfile.new(['ai-model-prices', '.csv'])
    csv.write("model,active\nfake-audio-model,true\n")
    csv.close

    expect { described_class.new(file: csv.path).perform }
      .to raise_error(ArgumentError, /CSV is missing headers/)
  ensure
    csv&.unlink
  end
end
