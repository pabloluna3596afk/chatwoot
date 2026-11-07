require 'rails_helper'

class ReasoningRequestBodyTestTool < RubyLLM::Tool
  description 'Returns a fixed answer for request body specs'
  parameter :query, description: 'Search query', required: true

  def name
    'search'
  end

  def execute(query:)
    query
  end
end

RSpec.describe 'RubyLLM reasoning request bodies' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }

  let(:responses_body) do
    {
      id: 'resp_test', object: 'response', created_at: Time.current.to_i, status: 'completed', model: 'gpt-6-luna',
      output: [{ id: 'msg_test', type: 'message', role: 'assistant', status: 'completed',
                 content: [{ type: 'output_text', text: 'Done', annotations: [] }] }],
      usage: { input_tokens: 4, output_tokens: 2, total_tokens: 6,
               input_tokens_details: { cached_tokens: 0 }, output_tokens_details: { reasoning_tokens: 0 } }
    }.to_json
  end

  let(:chat_completions_body) do
    {
      choices: [{ index: 0, message: { role: 'assistant', content: 'Done' }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 4, completion_tokens: 2, total_tokens: 6 }
    }.to_json
  end

  before do
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_ENDPOINT').destroy_all
    Llm::Config.refresh!
  end

  it 'sends assistant tool calls to Responses with reasoning.effort only' do
    payload = nil
    WebMock.stub_request(:post, %r{api\.openai\.com/v1/responses}).to_return do |request|
      payload = JSON.parse(request.body)
      { status: 200, body: responses_body, headers: { 'Content-Type' => 'application/json' } }
    end
    options = Captain::ResponsesConfig.options(model: 'gpt-6-luna', temperature: 0.5, feature: 'assistant')
    agent = Agents::Agent.new(
      name: 'Request body assistant', instructions: 'Use the search tool when needed.',
      model: 'gpt-6-luna', tools: [ReasoningRequestBodyTestTool.new], **options
    )

    Llm::Config.with_chat_context('test-api-key') do
      Llm::UsageContext.with(account: account, feature: 'assistant') do
        result = Agents::Runner.with_agents(agent).run('Search for an answer', context: {})
        expect(result.error).to be_nil
      end
    end

    expect(payload.dig('reasoning', 'effort')).to eq('none')
    expect(payload).not_to have_key('reasoning_effort')
    expect(payload['tools']).to include(include('type' => 'function', 'name' => 'search'))
  end

  it 'keeps reasoning_effort for Copilot tools on a custom Chat Completions endpoint' do
    endpoint = 'https://llm.example.test/openai'
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: endpoint)
    payload = nil
    WebMock.stub_request(:post, "#{endpoint}/v1/chat/completions").to_return do |request|
      payload = JSON.parse(request.body)
      { status: 200, body: chat_completions_body, headers: { 'Content-Type' => 'application/json' } }
    end

    Llm::Config.with_api_key('test-api-key', api_base: "#{endpoint}/v1") do |context|
      chat = context.chat(model: 'gpt-6-luna')
      chat = Captain::ResponsesConfig.configure_copilot_chat(
        chat, protocol: nil, model: 'gpt-6-luna', feature: 'copilot'
      ).with_tools(ReasoningRequestBodyTestTool.new)
      Llm::UsageContext.with(account: account, feature: 'copilot') do
        chat.ask('Search for an answer')
      end
    end

    expect(payload['reasoning_effort']).to eq('none')
    expect(payload).not_to have_key('reasoning')
    expect(payload['tools']).to include(include('type' => 'function', 'function' => include('name' => 'search')))
  end
end
