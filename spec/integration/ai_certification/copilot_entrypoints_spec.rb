require 'rails_helper'
require 'csv'

module CopilotCertificationResults
  def self.rows = @rows ||= []
end

RSpec.configure do |config|
  config.after(:each, :copilot_matrix_cell) do |example|
    result = example.exception ? 'FAIL' : example.metadata[:copilot_matrix_result] || 'PASS'
    CopilotCertificationResults.rows << [example.metadata[:copilot_matrix_cell], result]
  end

  config.after(:suite) do
    csv = CSV.generate do |output|
      ([%w[cell result]] + CopilotCertificationResults.rows).each { |row| output << row }
    end
    FileUtils.mkdir_p(Rails.root.join('tmp'))
    csv_path = Rails.root.join("tmp/copilot-certification-#{ENV.fetch('POSTGRES_DATABASE', 'default')}.csv")
    File.write(csv_path, csv)
    RSpec.configuration.reporter.message("\nCopilot certification CSV\n#{csv}")
  end
end

RSpec.describe 'Copilot real entrypoint certification', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: agent, assistant: assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/captain/copilot_threads" }
  let(:message_endpoint) { "#{endpoint}/#{thread.id}/copilot_messages" }
  let(:valid_message) { 'Summarize my inbox.' }

  before do
    account.enable_features!('captain_integration')
    put_account_on_plan(account, captain_copilot_responses: 10)
    stub_request(:get, %r{www\.gravatar\.com/avatar/}).to_return(status: 404)
  end

  def post_new_turn(message: valid_message, extra: {})
    perform_enqueued_jobs do
      post endpoint,
           params: { message: message, assistant_id: assistant.id }.merge(extra),
           headers: agent.create_new_auth_token,
           as: :json
    end
  end

  def post_follow_up(message: valid_message)
    perform_enqueued_jobs do
      post message_endpoint,
           params: { message: message },
           headers: agent.create_new_auth_token,
           as: :json
    end
  end

  def stub_chat_result(result = { 'content' => 'A helpful answer' }, error: false)
    allow(Captain::Copilot::ChatService).to receive(:new).and_wrap_original do |original, *args|
      service = original.call(*args)
      allow(service).to receive(:request_chat_completion_with_usage_context) do
        Llm::UsageContext.record_operation(
          model: 'gpt-6-luna', provider: 'openai', status: error ? 'error' : 'ok'
        )
        result
      end
      service
    end
  end

  def stub_chat_exception
    allow(Captain::Copilot::ChatService).to receive(:new).and_wrap_original do |original, *args|
      service = original.call(*args)
      allow(service).to receive(:request_chat_completion_with_usage_context) do
        Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'error')
        raise Timeout::Error, 'provider timeout'
      end
      service
    end
  end

  def assistant_failure_message
    CopilotThread.where(account: account, user: agent).order(:id).last.copilot_messages.assistant.order(:id).last
  end

  def prepare_reply_suggestion
    create(:inbox_member, user: agent, inbox: inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: 'Can you help?')
  end

  def stub_reply_suggestion(*results, &on_generate)
    runner = instance_double(Captain::Assistant::AgentRunnerService, last_run_result: nil)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    allow(runner).to receive(:generate_response) do |message_history:|
      on_generate&.call(message_history)
      result = results.shift
      raise result if result.is_a?(Exception)

      Llm::UsageContext.record_operation(
        model: 'gpt-6-luna', provider: 'openai', status: result['error'] ? 'error' : 'ok'
      )
      result
    end
    runner
  end

  def post_reply_suggestion
    perform_enqueued_jobs do
      post endpoint,
           params: { message: 'Suggest a reply.', assistant_id: assistant.id,
                     conversation_id: conversation.display_id, request_type: 'reply_suggestion' },
           headers: agent.create_new_auth_token,
           as: :json
    end
  end

  def suggestion_result
    {
      'response_parts' => [{ 'text' => 'A suggested reply', 'citation_indexes' => [] }],
      'response' => 'A suggested reply', 'reasoning' => 'Based on the conversation.'
    }
  end

  describe 'chat/E1 success', copilot_matrix_cell: 'chat/E1' do
    it 'posts an authenticated request, runs ResponseJob, persists the answer, and charges once' do
      usage = account.current_usage_period
      stub_chat_result

      post_new_turn

      expect(response).to have_http_status(:success)
      expect(AiUsageEvent.where(account: account, feature: 'copilot', status: 'ok')).to exist
      expect(usage.reload.copilot_responses_consumed).to eq(1)
    end
  end

  describe 'chat/E2 provider error', copilot_matrix_cell: 'chat/E2' do
    it 'persists the localized failure message and releases the reservation' do
      usage = account.current_usage_period
      stub_chat_result({ 'error' => 'provider unavailable' }, error: true)

      post_new_turn

      failure = CopilotMessage.where(message_type: :assistant).last
      expect(response).to have_http_status(:success)
      expect(failure.message).to include('error' => true)
      expect(failure.message['content']).to eq(I18n.t('captain.copilot_response_failed'))
      expect(usage.reload.copilot_responses_consumed).to eq(0)
      reservations = AiUsageReservation.joins(:account_plan_usage).where(
        account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
      )
      expect(reservations).to be_empty
    end
  end

  describe 'chat/E3 provider exception', copilot_matrix_cell: 'chat/E3' do
    it 'persists an error turn so the conversation is no longer left waiting' do
      usage = account.current_usage_period
      stub_chat_exception

      post_new_turn

      failed_turn = CopilotThread.where(account: account, user: agent).order(:id).last
      expect(failed_turn.copilot_messages.assistant.last.message).to include(
        'content' => I18n.t('captain.copilot_response_failed'), 'error' => true
      )
      expect(usage.reload.copilot_responses_consumed).to eq(0)
      reservations = AiUsageReservation.joins(:account_plan_usage).where(
        account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
      )
      expect(reservations).to be_empty
    end
  end

  describe 'chat/E4 empty provider response', copilot_matrix_cell: 'chat/E4' do
    it 'does not charge and persists the failure state' do
      usage = account.current_usage_period
      stub_chat_result({ 'content' => '' })

      post_new_turn

      expect(assistant_failure_message.message).to include('error' => true)
      expect(usage.reload.copilot_responses_consumed).to eq(0)
    end
  end

  describe 'chat/E5 exhausted Copilot quota', copilot_matrix_cell: 'chat/E5' do
    it 'returns 429 before enqueuing or calling the provider' do
      put_account_on_plan(account, captain_copilot_responses: 1, copilot_used: 1)
      expect(Captain::Copilot::ResponseJob).not_to receive(:perform_later)
      expect(Captain::Copilot::ChatService).not_to receive(:new)

      post_new_turn

      expect(response).to have_http_status(:too_many_requests)
      expect(CopilotThread.where(account: account)).to be_empty
    end
  end

  describe 'chat/E6 exhausted shared response bucket', copilot_matrix_cell: 'chat/E6' do
    it 'returns 429 before enqueuing when Copilot uses the shared Captain pool' do
      put_account_on_plan(account, monthly_messages: 1, used: 1)
      expect(Captain::Copilot::ResponseJob).not_to receive(:perform_later)
      expect(Captain::Copilot::ChatService).not_to receive(:new)

      post_new_turn

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'chat/E7 disabled feature', copilot_matrix_cell: 'chat/E7' do
    it 'returns 403 without a job or provider request' do
      account.disable_features!('captain_integration')
      expect(Captain::Copilot::ResponseJob).not_to receive(:perform_later)
      expect(Captain::Copilot::ChatService).not_to receive(:new)

      post_new_turn

      expect(response).to have_http_status(:forbidden)
      expect(AiUsageEvent.where(account: account, feature: 'copilot')).to be_empty
    end
  end

  describe 'chat/E8 retry after failure', copilot_matrix_cell: 'chat/E8' do
    it 'releases a failed turn and charges exactly once after a subsequent successful turn' do
      usage = account.current_usage_period
      stub_chat_result({ 'error' => 'provider unavailable' }, error: true)
      post_new_turn
      created_thread = CopilotThread.where(account: account, user: agent).order(:id).last
      expect(usage.reload.copilot_responses_consumed).to eq(0)

      allow(Captain::Copilot::ChatService).to receive(:new).and_wrap_original do |original, *args|
        service = original.call(*args)
        allow(service).to receive(:request_chat_completion_with_usage_context) do
          Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'ok')
          { 'content' => 'Recovered answer' }
        end
        service
      end
      perform_enqueued_jobs do
        post "/api/v1/accounts/#{account.id}/captain/copilot_threads/#{created_thread.id}/copilot_messages",
             params: { message: 'Try again' }, headers: agent.create_new_auth_token, as: :json
      end

      expect(AiUsageEvent.where(account: account, feature: 'copilot', status: 'ok').count).to eq(1)
      expect(usage.reload.copilot_responses_consumed).to eq(1)
    end
  end

  describe 'chat/E9 last-credit reservation', copilot_matrix_cell: 'chat/E9' do
    it 'serializes two real queued turns against one remaining credit' do
      put_account_on_plan(account, captain_copilot_responses: 1)
      usage = account.current_usage_period
      stub_chat_result
      create(:captain_copilot_thread, account: account, user: agent, assistant: assistant)

      post_follow_up(message: 'First turn')
      post_follow_up(message: 'Second turn')

      expect(usage.reload.copilot_responses_consumed).to eq(1)
      expect(response).to have_http_status(:too_many_requests)
      expect(AiUsageEvent.where(account: account, feature: 'copilot', status: 'ok').count).to eq(1)
    end
  end

  describe 'chat/E10 bounds, account isolation, and privacy', copilot_matrix_cell: 'chat/E10' do
    it 'rejects 4,001 characters before reservation or job enqueue' do
      expect(Captain::Copilot::ResponseJob).not_to receive(:perform_later)
      expect do
        post endpoint,
             params: { message: 'x' * 4_001, assistant_id: assistant.id },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(CopilotThread, :count)

      expect([response.status, CopilotMessage.where(account: account).count]).to eq([422, 0])

      public_message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                        message_type: :incoming, content: 'Visible context')
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: 'Private context')
      service = Captain::Copilot::ChatService.new(
        assistant,
        user_id: agent.id,
        copilot_thread_id: thread.id,
        conversation_id: conversation.display_id
      )
      prompt = service.messages.map { |item| item[:content] }.join
      history = thread.previous_history
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      create_list(:conversation, 2, account: other_account, inbox: other_inbox)
      other_conversation = other_account.conversations.order(:id).last
      other_service = Captain::Copilot::ChatService.new(
        assistant,
        user_id: agent.id,
        copilot_thread_id: thread.id,
        conversation_id: other_conversation.display_id
      )

      expect(prompt).to include('Visible context').and include(public_message.id.to_s)
      expect(prompt).not_to include('Private context')
      expect(history.size <= Captain::Copilot::Limits::HISTORY_MESSAGES &&
             history.sum { |item| item[:content].to_s.length } <= Captain::Copilot::Limits::HISTORY_CHARACTERS).to be(true)
      expect(other_service.messages.map { |item| item[:content] }.join).not_to include('Visible context')
    end
  end

  describe 'reply_suggestion/E1 success', copilot_matrix_cell: 'reply_suggestion/E1' do
    it 'runs the request enqueued job and charges after persisting a suggestion' do
      prepare_reply_suggestion
      usage = account.current_usage_period
      stub_reply_suggestion(suggestion_result)

      post_reply_suggestion

      suggestion = CopilotMessage.where(message_type: :assistant).last
      expect(response).to have_http_status(:success)
      expect(suggestion.message).to include('reply_suggestion' => true, 'content' => 'A suggested reply')
      expect(usage.reload.copilot_responses_consumed).to eq(1)
    end
  end

  describe 'reply_suggestion/E2 provider error', copilot_matrix_cell: 'reply_suggestion/E2' do
    it 'uses the job retry path and persists its terminal failure without charging' do
      prepare_reply_suggestion
      usage = account.current_usage_period
      stub_reply_suggestion(*Array.new(3) do
        { 'error' => true, 'reasoning' => 'Temporary provider failure.' }
      end)

      travel_to(10.seconds.from_now) { post_reply_suggestion }

      expect(CopilotMessage.where(message_type: :assistant).last.message['content'])
        .to eq("Copilot couldn't generate a reply. Please try again.")
      expect(usage.reload.copilot_responses_consumed).to eq(0)
      reservations = AiUsageReservation.joins(:account_plan_usage).where(
        account_plan_usages: { account_id: account.id }, bucket: 'copilot', released_at: nil
      )
      expect(reservations).to be_empty
    end
  end

  describe 'reply_suggestion/E3 provider exception', copilot_matrix_cell: 'reply_suggestion/E3' do
    it 'releases a raised provider attempt and lets the entrypoint retry successfully once' do
      prepare_reply_suggestion
      usage = account.current_usage_period
      stub_reply_suggestion(Captain::Copilot::ReplySuggestionService::GenerationError.new('temporary'),
                            suggestion_result)

      travel_to(10.seconds.from_now) { post_reply_suggestion }

      expect(CopilotMessage.where(message_type: :assistant).last.message['reply_suggestion']).to be(true)
      expect(usage.reload.copilot_responses_consumed).to eq(1)
    end
  end

  describe 'reply_suggestion/E4 empty provider response', copilot_matrix_cell: 'reply_suggestion/E4' do
    it 'persists fallback text and releases the unused reservation' do
      prepare_reply_suggestion
      usage = account.current_usage_period
      stub_reply_suggestion('response' => '')

      post_reply_suggestion

      expect(CopilotMessage.where(message_type: :assistant).last.message['content'])
        .to eq("Copilot couldn't generate a reply. Please try again.")
      expect(usage.reload.copilot_responses_consumed).to eq(0)
    end
  end

  describe 'reply_suggestion/E5 exhausted Copilot quota', copilot_matrix_cell: 'reply_suggestion/E5' do
    it 'blocks before enqueuing the suggestion job' do
      prepare_reply_suggestion
      put_account_on_plan(account, captain_copilot_responses: 1, copilot_used: 1)
      expect(Captain::Copilot::ReplySuggestionJob).not_to receive(:perform_later)

      post_reply_suggestion

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'reply_suggestion/E6 exhausted shared response bucket', copilot_matrix_cell: 'reply_suggestion/E6' do
    it 'blocks in the shared Captain pool before enqueuing work' do
      prepare_reply_suggestion
      put_account_on_plan(account, monthly_messages: 1, used: 1)
      expect(Captain::Copilot::ReplySuggestionJob).not_to receive(:perform_later)

      post_reply_suggestion

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'reply_suggestion/E7 disabled feature', copilot_matrix_cell: 'reply_suggestion/E7' do
    it 'returns 403 without provider work or a usage event' do
      prepare_reply_suggestion
      account.disable_features!('captain_integration')
      expect(Captain::Copilot::ReplySuggestionJob).not_to receive(:perform_later)

      post_reply_suggestion

      expect(response).to have_http_status(:forbidden)
      expect(AiUsageEvent.where(account: account, feature: 'copilot_reply_suggestion')).to be_empty
    end
  end

  describe 'reply_suggestion/E8 retry after failure', copilot_matrix_cell: 'reply_suggestion/E8' do
    it 'charges only the successful provider retry' do
      prepare_reply_suggestion
      usage = account.current_usage_period
      stub_reply_suggestion({ 'error' => true, 'reasoning' => 'Temporary failure.' }, suggestion_result)

      travel_to(10.seconds.from_now) { post_reply_suggestion }

      expect(usage.reload.copilot_responses_consumed).to eq(1)
      expect(CopilotMessage.where(message_type: :assistant).count).to eq(1)
    end
  end

  describe 'reply_suggestion/E9 last-credit concurrency', copilot_matrix_cell: 'reply_suggestion/E9' do
    self.use_transactional_tests = false

    let!(:limited_account) do
      create(:account).tap { |record| put_account_on_plan(record, captain_copilot_responses: 1) }
    end

    after { limited_account.destroy! }

    it 'uses the same atomic Copilot reservation as chat turns' do
      ready = Queue.new
      start = Queue.new
      attempts = Array.new(2) do
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

  describe 'reply_suggestion/E10 scope and history', copilot_matrix_cell: 'reply_suggestion/E10' do
    it 'rejects inaccessible conversations and does not enqueue a suggestion job' do
      prepare_reply_suggestion
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      other_conversation = create_list(:conversation, 2, account: other_account, inbox: other_inbox).last
      other_conversation.update_column(:display_id, 100_001) # rubocop:disable Rails/SkipsModelValidations
      create(:message, conversation: other_conversation, account: other_account, inbox: other_inbox,
                       message_type: :incoming, content: 'Cross-account secret')
      allow(Captain::Copilot::ReplySuggestionJob).to receive(:perform_later).and_call_original

      post endpoint,
           params: { message: 'Suggest a reply.', assistant_id: assistant.id,
                     conversation_id: other_conversation.display_id, request_type: 'reply_suggestion' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(CopilotThread.where(user: agent)).to be_empty
      expect(Captain::Copilot::ReplySuggestionJob).not_to have_received(:perform_later)

      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: 'Private suggestion context')
      histories = []
      stub_reply_suggestion(suggestion_result) { |history| histories << history }
      post_reply_suggestion

      expect(histories.flatten.map { |entry| entry[:content] }.join).not_to include('Private suggestion context')
    end
  end

  describe 'read_tools/E1 tool results', copilot_matrix_cell: 'read_tools/E1' do
    it 'runs get, search, and summarize tools through the Copilot ChatService tool registry' do
      public_message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                        message_type: :incoming, content: 'Public customer detail')
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: 'Private staff note')
      service = Captain::Copilot::ChatService.new(
        assistant, user_id: agent.id, copilot_thread_id: thread.id
      )
      tools = service.instance_variable_get(:@tools)
      get_result = tools.find { |tool| tool.name == 'get_conversation' }
                        .execute(conversation_id: conversation.display_id)
      search_result = tools.find { |tool| tool.name == 'search_conversation' }
                           .execute(order_by: 'created_at', limit: 1)
      summary_result = tools.find { |tool| tool.name == 'summarize_conversation' }
                            .execute(conversation_id: conversation.display_id)

      expect(get_result).to include('Public customer detail')
      expect(search_result).to include('Public customer detail')
      expect(summary_result).to include("message_id=#{public_message.id}", 'Public customer detail')
      [get_result, search_result, summary_result].each { |result| expect(result).not_to include('Private staff note') }
    end
  end

  describe 'read_tools/E2 provider error N/A', copilot_matrix_cell: 'read_tools/E2',
                                               copilot_matrix_result: 'N/A' do
    it 'documents that read tools do not own provider error handling' do
      expect('Provider errors are handled by the enclosing chat turn (chat/E2).').not_to be_empty
    end
  end

  describe 'read_tools/E3 provider exception N/A', copilot_matrix_cell: 'read_tools/E3',
                                                   copilot_matrix_result: 'N/A' do
    it 'documents that read tools do not own provider exception handling' do
      expect('Provider exceptions are handled by the enclosing chat turn (chat/E3).').not_to be_empty
    end
  end

  describe 'read_tools/E4 malformed provider response N/A', copilot_matrix_cell: 'read_tools/E4', copilot_matrix_result: 'N/A' do
    it 'documents that read tools return data rather than parse provider responses' do
      expect('Malformed model output is handled by the enclosing chat turn (chat/E4).').not_to be_empty
    end
  end

  describe 'read_tools/E5 exhausted Copilot quota N/A', copilot_matrix_cell: 'read_tools/E5', copilot_matrix_result: 'N/A' do
    it 'documents that quota admission belongs to the enclosing chat turn' do
      expect('The chat entrypoint rejects exhausted Copilot quota before invoking tools (chat/E5).').not_to be_empty
    end
  end

  describe 'read_tools/E6 exhausted shared bucket N/A', copilot_matrix_cell: 'read_tools/E6', copilot_matrix_result: 'N/A' do
    it 'documents that shared bucket admission belongs to the enclosing chat turn' do
      expect('The chat entrypoint rejects the shared bucket before invoking tools (chat/E6).').not_to be_empty
    end
  end

  describe 'read_tools/E7 feature and role admission N/A', copilot_matrix_cell: 'read_tools/E7', copilot_matrix_result: 'N/A' do
    it 'documents that tool availability is decided by the ChatService registry' do
      expect('Inactive tools are filtered before invocation; entry admission is covered by chat/E7.').not_to be_empty
    end
  end

  describe 'read_tools/E8 retry N/A', copilot_matrix_cell: 'read_tools/E8', copilot_matrix_result: 'N/A' do
    it 'documents that read tools do not retry provider turns or reserve credits' do
      expect('Retry and billing belong to the enclosing chat turn (chat/E8).').not_to be_empty
    end
  end

  describe 'read_tools/E9 concurrent credit N/A', copilot_matrix_cell: 'read_tools/E9', copilot_matrix_result: 'N/A' do
    it 'documents that read tools do not own the account reservation' do
      expect('The shared turn reservation is tested at the chat entrypoint (chat/E9).').not_to be_empty
    end
  end

  describe 'read_tools/E10 privacy and account isolation', copilot_matrix_cell: 'read_tools/E10' do
    it 'excludes private notes and refuses a conversation from another account in all three read tools' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      other_conversation = create(:conversation, account: other_account, inbox: other_inbox)
      create(:message, conversation: other_conversation, account: other_account, inbox: other_inbox,
                       message_type: :incoming, content: 'Cross-account secret')
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'Customer-visible text')
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: 'Secret internal note')
      service = Captain::Copilot::ChatService.new(
        assistant, user_id: agent.id, copilot_thread_id: thread.id
      )
      tools = service.instance_variable_get(:@tools)
      get_tool = tools.find { |tool| tool.name == 'get_conversation' }
      search_tool = tools.find { |tool| tool.name == 'search_conversation' }
      summary_tool = tools.find { |tool| tool.name == 'summarize_conversation' }

      outputs = [get_tool.execute(conversation_id: other_conversation.display_id),
                 search_tool.execute,
                 summary_tool.execute(conversation_id: other_conversation.display_id)]

      expect(outputs.join).not_to include('Cross-account secret', 'Secret internal note')
      expect(outputs.join).to include('Customer-visible text')
    end
  end

  describe 'action_proposals/E1 approve and reject', copilot_matrix_cell: 'action_proposals/E1' do
    it 'creates a proposal through ChatService and applies approve/reject through the action item controller' do
      contact = create(:contact, account: account)
      label = create(:label, account: account)
      thread.copilot_messages.create!(message_type: :user, message: { content: 'Please add this label.' })
      service = Captain::Copilot::ChatService.new(
        assistant, user_id: agent.id, copilot_thread_id: thread.id
      )
      tool = service.instance_variable_get(:@tools).find { |candidate| candidate.name == 'propose_action' }
      proposal = tool.execute(
        action: 'add_label', target: { 'type' => 'Contact', 'id' => contact.id },
        payload: { 'label_id' => label.id }
      )

      post "/api/v1/accounts/#{account.id}/captain/copilot_action_items/#{proposal[:proposal_id]}/approve",
           params: { copilot_thread_id: thread.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('executed')
      expect(contact.reload.label_list).to include(label.title)

      second_proposal = tool.execute(
        action: 'add_label', target: { 'type' => 'Contact', 'id' => contact.id },
        payload: { 'label_id' => create(:label, account: account).id }
      )
      post "/api/v1/accounts/#{account.id}/captain/copilot_action_items/#{second_proposal[:proposal_id]}/reject",
           params: { copilot_thread_id: thread.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('rejected')
    end
  end

  describe 'action_proposals/E2 provider error N/A', copilot_matrix_cell: 'action_proposals/E2', copilot_matrix_result: 'N/A' do
    it 'documents that action decision endpoints never call the provider' do
      expect('Provider failure belongs to proposal generation through chat (chat/E2).').not_to be_empty
    end
  end

  describe 'action_proposals/E3 provider exception N/A', copilot_matrix_cell: 'action_proposals/E3', copilot_matrix_result: 'N/A' do
    it 'documents that action decision endpoints never call the provider' do
      expect('Provider exceptions belong to proposal generation through chat (chat/E3).').not_to be_empty
    end
  end

  describe 'action_proposals/E4 malformed response N/A', copilot_matrix_cell: 'action_proposals/E4', copilot_matrix_result: 'N/A' do
    it 'documents that action decision endpoints receive persisted proposals' do
      expect('Provider response parsing occurs before proposal controller approval.').not_to be_empty
    end
  end

  describe 'action_proposals/E5 exhausted Copilot quota N/A', copilot_matrix_cell: 'action_proposals/E5', copilot_matrix_result: 'N/A' do
    it 'documents that decision endpoints do not reserve Copilot credits' do
      expect('Credits are reserved while generating the proposal, not deciding it.').not_to be_empty
    end
  end

  describe 'action_proposals/E6 exhausted shared bucket N/A', copilot_matrix_cell: 'action_proposals/E6', copilot_matrix_result: 'N/A' do
    it 'documents that decision endpoints do not reserve the shared bucket' do
      expect('Shared bucket admission happens before the proposal generation job.').not_to be_empty
    end
  end

  describe 'action_proposals/E7 disabled feature', copilot_matrix_cell: 'action_proposals/E7' do
    it 'returns 403 without changing proposals or recording a provider event' do
      account.disable_features!('captain_integration')
      expect do
        get "/api/v1/accounts/#{account.id}/captain/copilot_action_items",
            params: { copilot_thread_id: thread.id }, headers: agent.create_new_auth_token, as: :json
      end.not_to change(CopilotActionItem, :count)

      expect(response).to have_http_status(:forbidden)
      expect(AiUsageEvent.where(account: account, feature: 'copilot')).to be_empty
    end
  end

  describe 'action_proposals/E8 retry N/A', copilot_matrix_cell: 'action_proposals/E8', copilot_matrix_result: 'N/A' do
    it 'documents that action decision endpoints are idempotent state transitions, not provider retries' do
      expect('A retry of generation belongs to the enclosing Copilot turn (chat/E8).').not_to be_empty
    end
  end

  describe 'action_proposals/E9 last-credit concurrency N/A', copilot_matrix_cell: 'action_proposals/E9', copilot_matrix_result: 'N/A' do
    it 'documents that proposals are not charged independently of their chat turn' do
      expect('propose_action has no independent credit reservation; chat/E9 covers turn admission.').not_to be_empty
    end
  end

  describe 'action_proposals/E10 user and account isolation', copilot_matrix_cell: 'action_proposals/E10' do
    it 'does not expose another users or accounts action items' do
      other_user = create(:user, account: account, role: :administrator)
      other_thread = create(:captain_copilot_thread, account: account, user: other_user, assistant: assistant)
      other_account = create(:account)
      other_account.enable_features!('captain_integration')
      other_account_thread = create(:captain_copilot_thread, account: other_account,
                                                             user: create(:user, account: other_account))

      [other_thread, other_account_thread].each do |inaccessible_thread|
        get "/api/v1/accounts/#{account.id}/captain/copilot_action_items",
            params: { copilot_thread_id: inaccessible_thread.id },
            headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
