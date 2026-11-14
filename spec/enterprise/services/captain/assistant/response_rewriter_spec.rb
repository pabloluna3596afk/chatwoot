require 'rails_helper'

RSpec.describe Captain::Assistant::ResponseRewriter do
  subject(:rewriter) { described_class.new(assistant: assistant, attribute_provider: nil) }

  let(:assistant) { create(:captain_assistant) }
  let(:parts) { Captain::Assistant::ResponseParts.new([{ 'text' => 'Una respuesta larga', 'citation_indexes' => [1] }]) }
  let(:result) do
    Struct.new(:context, :messages, :output).new(
      { session_id: 'eval', state: { account_id: assistant.account_id }, conversation_history: [{ role: 'assistant', content: 'original' }] },
      [{ role: 'assistant', content: 'original' }], {}
    )
  end
  let(:rewritten) { { 'response_parts' => [{ 'text' => 'Breve', 'citation_indexes' => [] }] } }
  let(:rewrite_result) { instance_double(Agents::RunResult, output: rewritten, failed?: false) }
  let(:model_runner) { instance_double(Agents::AgentRunner, run: rewrite_result) }

  before do
    allow(Agents::Runner).to receive(:with_agents).and_return(model_runner)
    allow(ChatwootApp).to receive(:otel_enabled?).and_return(false)
  end

  it 'shortens the output and preserves original citations in both histories' do
    allow(assistant).to receive(:citations_enabled?).and_return(false)
    expect(rewriter.rewrite(result, response_parts: parts, response_text_limit: 10)).to equal(result)
    expected = { 'text' => 'Breve', 'citation_indexes' => [1] }
    expect(result.output['response_parts']).to eq([expected])
    expect(result.messages.last[:content]).to eq(result.output)
    expect(result.context[:conversation_history].last[:content]).to eq(result.output)
  end

  it 'rejects an invalid response part count without modifying the original' do
    allow(rewrite_result).to receive(:output).and_return({ 'response_parts' => [] })
    expect { rewriter.rewrite(result, response_parts: parts, response_text_limit: 10) }.to raise_error(/number of response parts/)
    expect(result.output).to eq({})
  end

  it 'raises the provider error' do
    allow(rewrite_result).to receive_messages(failed?: true, error: RuntimeError.new('provider failure'))
    expect { rewriter.rewrite(result, response_parts: parts, response_text_limit: 10) }.to raise_error('provider failure')
  end

  it 'passes only the current account state to the rewrite call' do
    other_assistant = create(:captain_assistant)
    rewriter.rewrite(result, response_parts: parts, response_text_limit: 10)
    expect(model_runner).to have_received(:run).with(anything, context: hash_including(state: { account_id: assistant.account_id }), max_turns: 1)
    expect(result.context[:state][:account_id]).not_to eq(other_assistant.account_id)
  end
end
