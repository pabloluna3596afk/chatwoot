require 'rails_helper'
require 'tmpdir'

RSpec.describe Captain::Eval::Runner do
  subject(:runner) { described_class.new(env: { 'CAPTAIN_EVAL' => '1' }.merge(options)) }

  let(:options) { {} }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.01)) }
  let(:agent_runner) { instance_double(Captain::Assistant::AgentRunnerService, last_run_result: nil, handoff_completed?: false) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(agent_runner)
    allow(agent_runner).to receive(:generate_response).and_return({ 'response' => 'El horario es de 9:00 a 13:00.' })
  end

  it 'builds the conversation and returns the response for all 30 cases' do
    result = runner.perform
    data = JSON.parse(File.read(result[:json]))
    expect(data['cases'].size).to eq(30)
    expect(data['cases'].first['attempts'].first['response']).to eq('El horario es de 9:00 a 13:00.')
    expect(Conversation.where(account_id: data['account_id']).count).to eq(30)
    expect(agent_runner).to have_received(:generate_response).with(message_history: array_including(hash_including(role: 'user'))).at_least(:once)
    expect(agent_runner).to have_received(:generate_response).with(
      message_history: array_including(hash_including(role: 'assistant', content: 'El horario es de 9:00 a 13:00.'))
    ).at_least(:once)
    expect(File.read(result[:markdown])).to include('citas-01', 'tienda-10', 'servicios-10')
  end

  it 'marks a raising case as failed and continues' do
    allow(agent_runner).to receive(:generate_response).and_raise('simulated failure')
    data = JSON.parse(File.read(runner.perform[:json]))
    expect(data['totals']).to include('total' => 30, 'failed' => 30)
    expect(data['cases'].last['attempts'].first['error']).to include('simulated failure')
  end

  it 'marks provider errors returned by the production runner as failures' do
    allow(agent_runner).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff', 'error' => true,
                                                                    'reasoning' => 'Provider failed' })
    data = JSON.parse(File.read(runner.perform[:json]))
    expect(data['totals']['failed']).to eq(30)
    expect(data['cases'].first['attempts'].first['error']).to include('Provider failed')
  end

  it 'marks timed out cases as failed and continues' do
    allow(Timeout).to receive(:timeout).with(90).and_raise(Timeout::Error, 'case timed out')
    data = JSON.parse(File.read(runner.perform[:json]))
    expect(data['totals']['failed']).to eq(30)
    expect(data['cases'].last['attempts'].first['error']).to include('Timeout::Error')
  end

  it 'requires completed handoff metadata and an open conversation' do
    allow(Captain::Assistant::AgentRunnerService).to receive(:new) do |**args|
      args[:conversation].open!
      agent_runner
    end
    allow(agent_runner).to receive_messages(last_run_result: instance_double(Agents::RunResult, context: { captain_v2_handoff_tool_called: true }),
                                            handoff_completed?: true)
    data = JSON.parse(File.read(runner.perform[:json]))
    expect(data['cases'].find { |item| item['id'] == 'citas-05' }['passed']).to be true
    expect(data['cases'].find { |item| item['id'] == 'citas-07' }['passed']).to be false
  end

  it 'records names from the existing tool callback' do
    allow(Captain::Assistant::AgentRunnerService).to receive(:new) do |**args|
      args[:run_options].callbacks[:on_tool_start].call('sofia--faq_lookup', {}, nil)
      agent_runner
    end
    data = JSON.parse(File.read(runner.perform[:json]))
    attempt = data['cases'].find { |item| item['id'] == 'citas-01' }['attempts'].first
    expect(attempt['tools']).to eq(['faq_lookup'])
    expect(attempt['passed']).to be true
  end

  context 'with repeated cases' do
    let(:options) { { 'REPEAT' => '2', 'CASES' => 'citas' } }

    it 'requires every attempt to pass' do
      verticals = Captain::Eval::Suite.new(names: 'citas').verticals.map do |vertical|
        vertical.merge('cases' => [vertical['cases'].find { |item| item['id'] == 'citas-07' }])
      end
      allow(Captain::Eval::Suite).to receive(:new).and_return(
        instance_double(Captain::Eval::Suite, verticals: verticals)
      )
      allow(agent_runner).to receive(:generate_response).and_return({ 'response' => 'Hola, ¿en qué puedo ayudarte?' }, { 'response' => 'x' * 201 })
      data = JSON.parse(File.read(runner.perform[:json]))
      expect(data['cases'].size).to eq(1)
      expect(data['cases'].first['attempts'].size).to eq(2)
      expect(data['cases'].first['attempts'].pluck('passed')).to eq([true, false])
      expect(data['cases'].first['passed']).to be false
    end
  end

  context 'with MAX_DISTANCE' do
    let(:options) { { 'MAX_DISTANCE' => '0.45' } }

    it 'restores CAPTAIN_FAQ_MAX_DISTANCE even when the run raises' do
      config = InstallationConfig.find_or_create_by!(name: 'CAPTAIN_FAQ_MAX_DISTANCE') { |record| record.value = '0.61' }
      original = config.serialized_value.deep_dup
      allow(Captain::Eval::Sandbox).to receive(:new) do
        expect(Captain::Knowledge::Relevance.max_distance).to eq(0.45)
        raise 'sandbox failed'
      end
      expect { runner.perform }.to raise_error('sandbox failed')
      expect(config.reload.serialized_value).to eq(original)
    end

    it 'removes an override that did not exist before the run' do
      InstallationConfig.where(name: 'CAPTAIN_FAQ_MAX_DISTANCE').delete_all
      allow(Captain::Eval::Sandbox).to receive(:new).and_raise('sandbox failed')
      expect { runner.perform }.to raise_error('sandbox failed')
      expect(InstallationConfig.exists?(name: 'CAPTAIN_FAQ_MAX_DISTANCE')).to be false
    end

    it 'restores the threshold after success' do
      previous = Captain::Knowledge::Relevance.max_distance
      runner.perform
      expect(Captain::Knowledge::Relevance.max_distance).to eq(previous)
    end
  end
end
