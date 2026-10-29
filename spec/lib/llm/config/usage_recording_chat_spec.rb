require 'rails_helper'

class AiUsageLedgerTestTool < RubyLLM::Tool
  description 'Returns a fixed tool result for AI usage recording specs'
  parameter :query, description: 'Text to search', required: true

  def name
    'ai_usage_ledger_test_tool'
  end

  def execute(_tool_context, query:)
    "Found: #{query}"
  end
end

RSpec.describe Llm::Config::UsageRecordingChat do
  it 'records each provider request, including tool rounds, in the same usage group' do
    account = create(:account)
    AiModelPrice.create!(model: 'gpt-6-luna', input_per_million: 0.10,
                         cached_input_per_million: 0.02, output_per_million: 0.50,
                         effective_from: 1.day.ago)
    group_id = SecureRandom.uuid
    responses = [
      {
        choices: [{ index: 0, message: { role: 'assistant', content: nil, tool_calls: [{
          id: 'call-usage-ledger', type: 'function',
          function: { name: 'ai_usage_ledger_test_tool', arguments: '{"query":"answer"}' }
        }] }, finish_reason: 'tool_calls' }],
        usage: { prompt_tokens: 100, completion_tokens: 10, total_tokens: 110 }
      },
      {
        choices: [{ index: 0, message: { role: 'assistant', content: nil, tool_calls: [{
          id: 'call-usage-ledger-second', type: 'function',
          function: { name: 'ai_usage_ledger_test_tool', arguments: '{"query":"again"}' }
        }] }, finish_reason: 'tool_calls' }],
        usage: { prompt_tokens: 120, completion_tokens: 20, total_tokens: 140 }
      },
      {
        choices: [{ index: 0, message: { role: 'assistant', content: 'Tool result used', refusal: nil }, finish_reason: 'stop' }],
        usage: { prompt_tokens: 150, completion_tokens: 25, total_tokens: 175 }
      }
    ]
    request_stub = WebMock.stub_request(:post, %r{api\.openai\.com/v1/chat/completions})
    request_stub.to_return(*responses.map { |body| { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } } })

    agent = Agents::Agent.new(
      name: 'Usage ledger test agent', instructions: 'Use the tool when asked.',
      model: 'gpt-6-luna', provider: :openai, protocol: :chat_completions, tools: [AiUsageLedgerTestTool.new]
    )
    runner = Agents::Runner.with_agents(agent)

    Llm::Config.refresh!
    Llm::Config.with_chat_context('test-api-key') do
      Llm::UsageContext.with(account: account, bucket: :captain_responses, feature: 'captain_reply',
                             usage_group_id: group_id) do
        result = runner.run('Use the tool twice, then answer', context: {})
        expect(result.error).to be_nil
      end
    end

    events = AiUsageEvent.where(usage_group_id: group_id).order(:created_at)
    expect(events.count).to eq(3)
    expect(events.pluck(:input_tokens, :output_tokens)).to eq([[100, 10], [120, 20], [150, 25]])
    expect(events.pluck(:bucket).uniq).to eq(['captain_responses'])
    expect(events.sum(:cost_usd)).to be > 0
    expect(WebMock).to have_requested(:post, %r{api\.openai\.com/v1/chat/completions}).times(3)
  end
end
