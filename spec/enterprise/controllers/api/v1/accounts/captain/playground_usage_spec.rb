require 'rails_helper'

RSpec.describe 'Captain playground quotas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground" }
  let(:headers) { admin.create_new_auth_token }
  let(:params) { { message_content: 'Hello', message_history: [] } }
  let(:model) { instance_double(Captain::Llm::AssistantChatService) }

  before do
    put_account_on_plan(account)
    account.disable_features!('captain_integration_v2')
    allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(model)
    allow(model).to receive(:generate_response).and_return({ 'response' => 'Hello back' })
  end

  after do
    Redis::Alfred.delete("captain:playground:rate:#{account.id}")
    Redis::Alfred.delete("captain:playground:daily:#{account.id}:#{Time.current.utc.to_date}")
  end

  it 'serializes test_usage for v1 and persists only one debit' do
    post endpoint, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['response']).to eq('Hello back')
    expect(response.parsed_body['test_usage']).to include('plan_kind' => 'free', 'daily_remaining' => 0, 'plan_remaining' => 99)
    expect(captain_responses_used(account)).to eq(1)
  end

  it 'applies the same quota to the onboarding v2 runner' do
    account.enable_features!('captain_integration_v2')
    account.update!(custom_attributes: { onboarding_version: 2, onboarding_step: 'assistant', onboarding_assistant_id: assistant.id })
    runner = instance_double(Captain::Assistant::AgentRunnerService, generate_response: { 'response' => 'V2 reply' })
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    post endpoint, params: params, headers: headers, as: :json
    expect(response.parsed_body['response']).to eq('V2 reply')
    expect(response.parsed_body['test_usage']).to include('plan_kind' => 'free', 'plan_remaining' => 99)
    expect(Captain::Llm::AssistantChatService).not_to have_received(:new)
  end

  it 'applies the paid daily allowance and subsequent shared pool debit in the regular v2 panel' do
    account.plan.update!(price_monthly: 79, captain_daily_tests: 1)
    account.enable_features!('captain_integration_v2')
    runner = instance_double(Captain::Assistant::AgentRunnerService, generate_response: { 'response' => 'V2 reply' })
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    post endpoint, params: params, headers: headers, as: :json
    expect(response.parsed_body['test_usage']).to include('daily_used' => 1, 'plan_remaining' => 100)
    post endpoint, params: params, headers: headers, as: :json
    expect(response.parsed_body['test_usage']).to include('daily_used' => 1, 'plan_remaining' => 99)
    expect(captain_responses_used(account)).to eq(1)
  end

  it 'returns a stable 422 at zero plan availability without calling the model' do
    put_account_on_plan(account, used: 100)
    post endpoint, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error_code']).to eq('responses_limit_reached')
    expect(response.parsed_body['test_usage']['plan_remaining']).to eq(0)
    expect(model).not_to have_received(:generate_response)
  end

  it 'returns translated plan exhaustion with no daily allowance for a free plan' do
    account.update!(locale: 'es')
    account.current_usage_period.update!(responses_consumed: 100)
    post endpoint, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error_code']).to eq('responses_limit_reached')
    expect(response.parsed_body['error']).to eq('Se agotaron las respuestas de tu plan')
    expect(model).not_to have_received(:generate_response)
  end

  it 'returns Retry-After on the seventh request in a rolling minute' do
    6.times { post endpoint, params: params, headers: headers, as: :json }
    post endpoint, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body['error_code']).to eq('playground_rate_limit')
    expect(response.headers['Retry-After'].to_i).to be_between(1, 60)
    expect(model).to have_received(:generate_response).exactly(6).times
  end

  it 'rejects oversized input before model construction' do
    post endpoint, params: params.merge(message_content: 'a' * 501), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error_code']).to eq('playground_message_invalid')
    expect(Captain::Llm::AssistantChatService).not_to have_received(:new)
  end

  it 'caps model history and does not debit model failures' do
    history = Array.new(20) { { role: 'assistant', content: 'a' * 500 } }
    allow(model).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff', 'error' => true })
    post endpoint, params: params.merge(message_history: history), headers: headers, as: :json
    expect(model).to have_received(:generate_response).with(message_history: history.last(7) + [{ role: 'user', content: 'Hello' }])
    expect(response.parsed_body['test_usage']['plan_remaining']).to eq(100)
    expect(captain_responses_used(account)).to eq(0)
  end

  it 'exposes the allowance before the first question' do
    account.plan.update!(price_monthly: 79, captain_daily_tests: 10)
    get "#{endpoint}_usage", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['test_usage']).to include('plan_kind' => 'paid', 'daily_total' => 10, 'daily_used' => 0)
    expect(model).not_to have_received(:generate_response)
  end

  it 'scopes an existing own key around the model without metering' do
    hook = build(:integrations_hook, :openai, account: account)
    hook.save!(validate: false)
    expect(Llm::Config).to receive(:with_chat_context).with('api_key').and_yield
    post endpoint, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['test_usage']).to be_nil
    expect(captain_responses_used(account)).to eq(0)
  end
end
