require 'rails_helper'

RSpec.describe Captain::Eval::Checks do
  subject(:checks) { described_class.new(response: 'El horario del sábado es de 9:00 a 13:00. Gracias.', tools: ['faq_lookup'], handoff: false) }

  {
    'includes_any' => [%w[SÁBADO domingo], %w[lunes martes]],
    'includes_all' => [['SABADO', '13:00'], ['sábado', '18:00']],
    'excludes' => [%w[domingo lunes], %w[sabado]],
    'max_chars' => [100, 5],
    'tool_called' => %w[faq_lookup handoff],
    'tool_not_called' => %w[handoff faq_lookup],
    'handoff' => [false, true],
    'language' => %w[es en]
  }.each do |name, (valid, invalid)|
    it "passes #{name} with matching input" do
      expect(checks.perform(name => valid).sole[:passed]).to be true
    end

    it "fails #{name} with nonmatching input and gives a reason" do
      result = checks.perform(name => invalid).sole
      expect(result[:passed]).to be false
      expect(result[:reason]).to include(name)
    end
  end

  it 'recognizes English with the local vocabulary' do
    english = described_class.new(response: 'Our shop is open on Saturday. How can we help you?', tools: [], handoff: false)
    expect(english.language('en')).to be true
    expect(english.language('es')).to be false
  end

  it 'fails an ambiguous or empty language sample' do
    expect(described_class.new(response: '123', tools: [], handoff: false).language('es')).to be false
  end
end
