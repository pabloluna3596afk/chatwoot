require 'rails_helper'
require 'tmpdir'

RSpec.describe Captain::Eval::Report do
  let(:account) { create(:account) }
  let(:started_at) { 1.minute.ago }
  let(:results) do
    [{ id: 'citas-01', vertical: 'citas', type: '01', passed: false,
       attempts: [{ passed: false, response: "Respuesta completa | con salto\ny más texto", error: 'error simulado' }] }]
  end

  it 'writes markdown and json with totals and the complete failed response' do
    Dir.mktmpdir do |directory|
      files = described_class.new(results: results, account: account, started_at: started_at, directory: directory).write
      data = JSON.parse(File.read(files[:json]))
      expect(data['totals']).to include('total' => 1, 'failed' => 1, 'pass_percent' => 0)
      expect(data['by_vertical']['citas']['failed']).to eq(1)
      expect(data['by_type']['01']['failed']).to eq(1)
      expect(File.read(files[:markdown])).to include('Respuesta completa &#124; con salto<br>y más texto', 'error simulado')
    end
  end

  it 'reports unconfigured pricing instead of a zero cost and isolates account and time' do
    attributes = { bucket: 'captain_responses', feature: 'captain_reply', provider: 'openai', model: 'unpriced-eval',
                   usage_group_id: SecureRandom.uuid, status: 'ok', input_tokens: 100, output_tokens: 20,
                   cost_usd: 0, units: 1, created_at: Time.current }
    AiUsageEvent.create!(attributes.merge(account: account))
    AiUsageEvent.create!(attributes.merge(account: create(:account), cost_usd: 9))
    AiUsageEvent.create!(attributes.merge(account: account, cost_usd: 7, created_at: 1.day.ago))
    data = described_class.new(results: results, account: account, started_at: started_at).to_h
    expect(data[:usage]).to include(pricing: 'tarifa no configurada', unpriced_models: ['unpriced-eval'], event_count: 1)
    expect(data[:usage][:tokens]).to include(input_tokens: 100, output_tokens: 20)
  end

  it 'sums recorded cost and tokens when the model has a configured price' do
    AiModelPrice.create!(model: 'priced-eval', effective_from: 1.day.ago, active: true,
                         input_per_million: 1, cached_input_per_million: 0.5, output_per_million: 2)
    2.times do
      AiUsageEvent.create!(account: account, bucket: 'captain_responses', feature: 'captain_reply', provider: 'openai', model: 'priced-eval',
                           usage_group_id: SecureRandom.uuid, status: 'ok', input_tokens: 100, output_tokens: 20,
                           cost_usd: '0.00014', units: 1, created_at: Time.current)
    end
    usage = described_class.new(results: results, account: account, started_at: started_at).to_h[:usage]
    expect(BigDecimal(usage[:cost_usd])).to eq(BigDecimal('0.00028'))
    expect(usage[:tokens]).to include(input_tokens: 200, output_tokens: 40)
    expect(usage[:pricing]).to eq('configurada')
  end

  it 'also labels an all-zero placeholder tariff as unconfigured' do
    AiModelPrice.create!(model: 'zero-eval', effective_from: 1.day.ago, active: true,
                         input_per_million: 0, cached_input_per_million: 0, output_per_million: 0)
    AiUsageEvent.create!(account: account, bucket: 'captain_responses', feature: 'captain_reply', provider: 'openai', model: 'zero-eval',
                         usage_group_id: SecureRandom.uuid, status: 'ok', input_tokens: 100, cost_usd: 0, units: 1, created_at: Time.current)
    usage = described_class.new(results: results, account: account, started_at: started_at).to_h[:usage]
    expect(usage).to include(pricing: 'tarifa no configurada', unpriced_models: ['zero-eval'])
  end
end
