require 'rails_helper'

RSpec.describe Captain::Knowledge::Relevance do
  let(:near) { Struct.new(:neighbor_distance).new(0.20) }
  let(:boundary) { Struct.new(:neighbor_distance).new(0.55) }
  let(:far) { Struct.new(:neighbor_distance).new(0.80) }

  it 'keeps results at or under the threshold when filtering' do
    expect(described_class.apply([near, boundary], filter: true).kept).to eq([near, boundary])
  end

  it 'drops results over the threshold when filtering' do
    expect(described_class.apply([near, far], filter: true).kept).to eq([near])
  end

  it 'keeps everything when not filtering but still reports the best distance' do
    result = described_class.apply([far, near], filter: false)

    expect(result.kept).to eq([far, near])
    expect(result.best_distance).to eq(0.20)
    expect(result.filtered).to be false
  end

  it 'keeps a result without distance' do
    responses = [Struct.new(:neighbor_distance).new(nil), Object.new]

    expect(described_class.apply(responses, filter: true).kept).to eq(responses)
  end

  it 'handles an empty search' do
    result = described_class.apply([], filter: true)

    expect(result.kept).to eq([])
    expect(result.best_distance).to be_nil
  end

  it 'uses 0.55 when the setting is missing' do
    expect(described_class.max_distance).to eq(0.55)
  end

  it 'uses the installation setting when present and reads changes without restarting' do
    setting = create(:installation_config, name: described_class::CONFIG_NAME, value: '0.30')

    expect(described_class.apply([near, boundary], filter: true).threshold).to eq(0.30)
    expect(described_class.apply([near, boundary], filter: true).kept).to eq([near])
    setting.update!(value: '0.60')
    expect(described_class.apply([near, boundary], filter: true).kept).to eq([near, boundary])
  end

  { '0.01' => 0.20, '1.5' => 1.00, 'invalid' => 0.55, '' => 0.55 }.each do |value, expected|
    it "uses #{expected} for installation setting #{value.inspect}" do
      create(:installation_config, name: described_class::CONFIG_NAME, value: value)

      expect(described_class.max_distance).to eq(expected)
    end
  end
end
