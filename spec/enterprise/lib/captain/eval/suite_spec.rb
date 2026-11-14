require 'rails_helper'
require 'tmpdir'

RSpec.describe Captain::Eval::Suite do
  let(:data) { YAML.safe_load_file(File.join(described_class::DIRECTORY, 'citas.yml')) }

  it 'loads a valid file and all 30 cases with 24 knowledge pairs' do
    suite = described_class.new
    expect(suite.verticals.sum { |vertical| vertical.fetch('cases').size }).to eq(30)
    expect(suite.verticals.sum { |vertical| vertical.fetch('knowledge').size }).to eq(24)
  end

  it 'selects requested verticals' do
    expect(described_class.new(names: 'citas,tienda').verticals.pluck('vertical')).to eq(%w[citas tienda])
  end

  it 'rejects an unknown vertical' do
    expect { described_class.new(names: '../unknown') }.to raise_error(described_class::InvalidSuite, /Vertical desconocida/)
  end

  {
    'case without id' => ->(data) { data['cases'].first.delete('id') },
    'unknown check' => ->(data) { data['cases'].first['expect']['judge'] = true },
    'invalid boolean' => ->(data) { data['cases'].first['expect']['handoff'] = 'false' },
    'invalid turns' => ->(data) { data['cases'].first['turns'] = [nil] },
    'missing assistant' => ->(data) { data.delete('assistant') },
    'duplicate id' => ->(data) { data['cases'][1]['id'] = data['cases'][0]['id'] }
  }.each do |name, mutate|
    it "rejects a #{name}" do
      mutate.call(data)
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, 'citas.yml'), data.to_yaml)
        expect { described_class.new(directory: directory) }.to raise_error(described_class::InvalidSuite)
      end
    end
  end
end
