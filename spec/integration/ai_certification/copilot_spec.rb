require 'rails_helper'
require 'csv'

module CopilotCertificationResults
  def self.rows = @rows ||= []
end

RSpec.configure do |config|
  config.after(:each, :copilot_certification) do |example|
    CopilotCertificationResults.rows << [example.full_description, example.exception ? 'FAIL' : 'PASS']
  end

  config.after(:suite) do
    csv = CSV.generate do |rows|
      ([%w[scenario result]] + CopilotCertificationResults.rows).each { |row| rows << row }
    end
    RSpec.configuration.reporter.message("\nCopilot certification CSV\n#{csv}")
  end
end

# This integration spec covers several Copilot services, so it does not follow a unit spec filename.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Captain::Copilot::ChatService, :copilot_certification, type: :integration do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    put_account_on_plan(account)
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(true)
  end

  shared_examples 'a Copilot turn reservation' do |result|
    it 'charges one Copilot call only after a successful response' do
      usage = account.current_usage_period
      service = described_class.new(
        assistant, user_id: user.id, copilot_thread_id: thread.id
      )
      allow(service).to receive(:request_chat_completion_with_usage_context) do
        Llm::UsageContext.record_operation(
          model: 'gpt-6-luna', provider: 'openai', status: result['error'].present? ? 'error' : 'ok'
        )
        result
      end

      response = service.generate_response(nil)

      expect(response).to eq(result)
      successful = result['content'].present?
      expect(usage.reload.copilot_responses_consumed).to eq(successful ? 1 : 0)
      reservations = AiUsageReservation.joins(:account_plan_usage).where(
        account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
      )
      expect(reservations).to be_empty
      expect(AiUsageReservation.joins(:account_plan_usage).where(
        account_plan_usages: { account_id: account.id }, bucket: 'copilot'
      ).count).to eq(successful ? 0 : 1)
      expect(AiUsageEvent.where(account: account, feature: 'copilot').pluck(:status)).to eq(
        [result['error'].present? ? 'error' : 'ok']
      )
    end
  end

  describe 'chat turn reservation' do
    it_behaves_like 'a Copilot turn reservation', { 'content' => 'A helpful answer' }
    it_behaves_like 'a Copilot turn reservation', { 'content' => '' }

    context 'when the provider returns an error' do
      it_behaves_like 'a Copilot turn reservation', { 'error' => 'provider unavailable' }
    end

    it 'returns the disabled feature status before making a provider request' do
      allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(false)
      service = described_class.new(
        assistant, user_id: user.id, copilot_thread_id: thread.id
      )
      expect(service).not_to receive(:request_chat_completion)

      expect(service.generate_response(nil)).to include(error_code: 403)
      expect(AiUsageEvent.where(account: account, feature: 'copilot')).to be_empty
    end

    it 'releases the reservation and records an error when the provider raises' do
      usage = account.current_usage_period
      service = described_class.new(assistant, user_id: user.id, copilot_thread_id: thread.id)
      allow(service).to receive(:request_chat_completion_with_usage_context) do
        Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'error')
        raise Timeout::Error, 'provider timeout'
      end

      expect { service.generate_response(nil) }.to raise_error(Timeout::Error, 'provider timeout')
      expect(usage.reload.copilot_responses_consumed).to eq(0)
      expect(AiUsageReservation.joins(:account_plan_usage).where(
               account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
             )).to be_empty
      expect(AiUsageEvent.where(account: account, feature: 'copilot').pluck(:status)).to eq(['error'])
    end

    it 'keeps the first and subsequent persisted user messages in one turn each' do
      usage = account.current_usage_period
      results = [{ 'content' => 'First response' }, { 'content' => 'Second response' }]
      services = []
      2.times do |index|
        thread.copilot_messages.create!(message_type: 'user', message: { content: "Question #{index + 1}" })
        service_result = results[index]
        allow(described_class).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |service|
            services << service
            allow(service).to receive(:request_chat_completion_with_usage_context) do
              Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'ok')
              service_result
            end
          end
        end
        Captain::Copilot::ResponseJob.perform_now(
          assistant: assistant, conversation_id: nil, user_id: user.id,
          copilot_thread_id: thread.id, message: { content: "Question #{index + 1}" }
        )
      end

      expect(usage.reload.copilot_responses_consumed).to eq(2)
      expect(services.map { |service| service.previous_history.last[:content] }).to eq(
        ['Question 1', 'Question 2']
      )
      expect(AiUsageEvent.where(account: account, feature: 'copilot', status: 'ok').count).to eq(2)
    end
  end

  describe 'tool calls and proposals' do
    it 'allows twenty tool calls and rejects the twenty-first within one turn' do
      limiter = Captain::Copilot::ToolCallLimiter.new

      expect(Array.new(20) { limiter.consume! }).to eq((1..20).to_a)
      expect { limiter.consume! }.to raise_error(ArgumentError, 'Copilot allows at most 20 tool calls per turn')
    end

    it 'limits proposals and returns actionable errors without executing an action' do
      tool = Captain::Tools::Copilot::ProposeActionService.new(
        assistant, user: user, copilot_thread: thread
      )

      expect(tool.execute(action: 'missing_action', target: { 'type' => 'Contact', 'id' => 1 }, payload: {}))
        .to include(error: 'Unsupported action')
      expect(thread.copilot_action_items).to be_empty
    end
  end

  describe 'reply suggestion billing' do
    let(:runner) { instance_double(Captain::Assistant::AgentRunnerService, last_run_result: nil) }
    let(:response) do
      {
        'response_parts' => [{ 'text' => 'A suggested reply', 'citation_indexes' => [] }],
        'response' => 'A suggested reply', 'reasoning' => 'Based on the conversation.'
      }
    end

    before do
      create(:inbox_member, user: user, inbox: inbox)
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'Can you help?')
      allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
      allow(assistant).to receive(:trusted_citation_urls).with(nil).and_return({})
    end

    it 'consumes one credit and records the successful provider event' do
      usage = account.current_usage_period
      allow(runner).to receive(:generate_response) do
        Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'ok')
        response
      end
      service = Captain::Copilot::ReplySuggestionService.new(
        assistant: assistant, conversation_id: conversation.display_id,
        user_id: user.id, copilot_thread_id: thread.id
      )

      expect(service.generate_response).to eq(response)
      expect(usage.reload.copilot_responses_consumed).to eq(1)
      expect(AiUsageReservation.joins(:account_plan_usage).where(
               account_plan_usages: { account_id: account.id }, bucket: 'copilot'
             )).to be_empty
      expect(AiUsageEvent.where(account: account, feature: 'copilot_reply_suggestion').pluck(:status)).to eq(['ok'])
    end

    it 'releases the failed reservation and records the provider error' do
      usage = account.current_usage_period
      allow(runner).to receive(:generate_response) do
        Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'error')
        { 'error' => true, 'reasoning' => 'Provider unavailable.' }
      end
      service = Captain::Copilot::ReplySuggestionService.new(
        assistant: assistant, conversation_id: conversation.display_id,
        user_id: user.id, copilot_thread_id: thread.id
      )

      expect { service.generate_response }.to raise_error(Captain::Copilot::ReplySuggestionService::GenerationError)
      expect(usage.reload.copilot_responses_consumed).to eq(0)
      expect(AiUsageReservation.joins(:account_plan_usage).where(
               account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
             )).to be_empty
      expect(AiUsageEvent.where(account: account, feature: 'copilot_reply_suggestion').pluck(:status)).to eq(['error'])
    end
  end

  describe 'concurrent Copilot reservations' do
    self.use_transactional_tests = false

    let!(:limited_account) do
      create(:account).tap { |record| put_account_on_plan(record, captain_copilot_responses: 1) }
    end

    after { limited_account.destroy! }

    it 'admits only one reservation for the last Copilot credit' do
      ready = Queue.new
      start = Queue.new
      attempts = (1..2).map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            limited_account.reload.reserve_captain_ai_usage!(
              bucket: :copilot, reservation_id: SecureRandom.uuid
            )
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }

      expect(attempts.map(&:value).count(true)).to eq(1)
      expect(limited_account.reload.current_usage_period.copilot_responses_consumed).to eq(1)
    ensure
      attempts&.each { |attempt| attempt.kill if attempt.alive? }
      ActiveRecord::Base.connection_pool.release_connection
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
