require 'rails_helper'
require 'csv'

# rubocop:disable Rails/Output
RSpec.configure do |config|
  config.after(:suite) do
    examples = RSpec.world.all_examples.select { |example| example.metadata[:certification] == 'editor' }
    passed = examples.count { |example| example.execution_result.status == :passed }
    failed = examples.count { |example| example.execution_result.status == :failed }
    puts 'CERT_EDITOR_CSV_BEGIN'
    puts CSV.generate_line(['CERT_EDITOR_CLASSES', *Captain::BaseTaskService.descendants.filter_map(&:name).sort])
    puts CSV.generate_line(%w[class_flow scenario expected real status])
    examples.each do |example|
      status = example.execution_result.status
      puts CSV.generate_line(['Captain editor', example.full_description, 'contract assertions pass', status,
                              status == :passed ? 'PASS' : 'FAIL'])
    end
    puts "CERT_EDITOR_TOTALS,executed=#{examples.size},pass=#{passed},fail=#{failed}"
    puts 'CERT_EDITOR_CSV_END'
  end
end
# rubocop:enable Rails/Output

Rails.application.eager_load!

RSpec.describe 'Captain editor task certification', certification: 'editor', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/tasks" }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:mock_chat) { instance_double(RubyLLM::Chat, with_instructions: nil, ask: mock_llm_response) }
  let(:mock_context) { instance_double(RubyLLM::Context, chat: mock_chat) }
  let(:mock_llm_response) do
    instance_double(
      RubyLLM::Message,
      content: 'A generated response',
      parsed: { 'points' => [] },
      tokens: instance_double(RubyLLM::Tokens, input: 10, output: 5)
    )
  end

  before do
    put_account_on_plan(account, captain_internal_calls: 1)
    account.enable_features!('captain_tasks')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'certification-key')
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:add_message).and_return(mock_chat)
  end

  def post_task(action, params)
    post "#{url}/#{action}", params: params, headers: headers, as: :json
    response
  end

  describe 'HTTP task routes' do
    it 'returns the parsed successful reply suggestion from the real controller and service' do
      allow(mock_llm_response).to receive(:content).and_return('A helpful reply')

      result = post_task(:reply_suggestion, conversation_display_id: conversation.display_id)

      expect(result).to have_http_status(:ok), result.parsed_body.inspect
      expect(result.parsed_body).to include('message' => 'A helpful reply')
    end

    it 'returns the parsed successful summary from the real controller and service' do
      allow(mock_llm_response).to receive(:content).and_return('A concise summary')

      result = post_task(:summarize, conversation_display_id: conversation.display_id)

      expect(result).to have_http_status(:ok)
      expect(result.parsed_body).to include('message' => 'A concise summary')
    end

    it 'returns the parsed successful rewrite from the real controller and service' do
      allow(mock_llm_response).to receive(:content).and_return('A clearer draft')

      result = post_task(:rewrite, content: 'Draft', operation: 'improve',
                                   conversation_display_id: conversation.display_id)

      expect(result).to have_http_status(:ok)
      expect(result.parsed_body).to include('message' => 'A clearer draft')
    end

    it 'returns a parsed follow-up and its continuation context' do
      allow(mock_llm_response).to receive(:content).and_return('A refined reply')
      context = {
        event_name: 'improve', original_context: 'Draft', last_response: 'Better draft',
        conversation_history: [], channel_type: 'Channel::WebWidget'
      }

      result = post_task(
        :follow_up,
        conversation_display_id: conversation.display_id,
        follow_up_context: context,
        message: 'Shorter please'
      )

      expect(result).to have_http_status(:ok), result.parsed_body.inspect
      expect(result.parsed_body).to include('message' => 'A refined reply')
      expect(result.parsed_body.fetch('follow_up_context')).to include('last_response' => 'A refined reply')
    end

    it 'returns a parsed label suggestion from the real controller and service' do
      create_list(:message, 3, message_type: :incoming, account: account, inbox: inbox, conversation: conversation)
      create(:label, account: account, title: 'billing')
      allow(mock_llm_response).to receive(:content).and_return('labels: billing')

      result = post_task(:label_suggestion, conversation_display_id: conversation.display_id)

      expect(result).to have_http_status(:ok)
      expect(result.parsed_body).to include('message' => ' billing')
    end

    it 'preserves a provider error status and does not charge the internal quota' do
      allow(mock_chat).to receive(:ask).and_raise(Timeout::Error, 'provider failed')

      result = post_task(:rewrite, content: 'Draft', operation: 'improve',
                                   conversation_display_id: conversation.display_id)

      expect(result).to have_http_status(:bad_gateway)
      expect(result.parsed_body).to include('error_code' => 502)
      expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
    end

    it 'returns 429 before calling the service when the internal quota is exhausted' do
      account.current_usage_period.update!(internal_calls_consumed: 1)
      expect(mock_chat).not_to receive(:ask)

      result = post_task(:rewrite, content: 'Draft', operation: 'improve')

      expect(result).to have_http_status(:too_many_requests)
      expect(result.parsed_body).to include('error_code' => 429)
      expect(AiUsageEvent.where(account_id: account.id)).to be_empty
    end

    it 'returns 403 before calling the service when the task feature is disabled' do
      account.disable_features!('captain_tasks')
      expect(mock_chat).not_to receive(:ask)

      result = post_task(:rewrite, content: 'Draft', operation: 'improve')

      expect(result).to have_http_status(:forbidden)
      expect(result.parsed_body).to include('error_code' => 403)
      expect(AiUsageEvent.where(account_id: account.id)).to be_empty
    end
  end

  describe 'reflected BaseTaskService descendants' do
    it 'discovers the complete family and verifies Enterprise usage wrapping' do
      Rails.application.eager_load!
      descendants = Captain::BaseTaskService.descendants.sort_by(&:name)

      expect(descendants).not_to be_empty
      expect(descendants).to all(satisfy { |service_class|
        service_class.ancestors.include?(Enterprise::Captain::BaseTaskService)
      })
      descendants.each do |service_class|
        service = service_class.allocate
        service.define_singleton_method(:operation) { :improve }
        feature = service.send(:event_name)

        expect { Llm::UsageContext.bucket_for(feature) }.not_to raise_error, "#{service_class} emits unmapped feature #{feature.inspect}"
      end
    end

    RSpec.shared_examples 'the Captain task reservation contract' do |service_name|
      let(:parent_service_class) { Object.const_get(service_name) }
      let(:usage_config) do
        service = parent_service_class.allocate
        service.define_singleton_method(:operation) { :improve }
        feature = service.send(:event_name)
        bucket = Llm::UsageContext.bucket_for(feature)
        {
          feature: feature,
          bucket: bucket,
          counter_column: bucket == :internal ? :internal_calls_consumed : :responses_consumed,
          required_gate: if bucket == :internal || Llm::Entitlement::TASK_FEATURE_GATES.include?(feature)
                           'captain_tasks'
                         else
                           'captain_integration'
                         end
        }
      end
      let(:service_class) do
        parent = parent_service_class
        feature = usage_config[:feature]
        Class.new(parent) do
          define_method(:initialize) do |account:, result: nil, failure: nil|
            @account = account
            @certification_result = result
            @certification_failure = failure
          end

          define_method(:account) { @account }

          define_method(:perform) do
            if @certification_failure
              Llm::UsageContext.record_operation(model: 'gpt-5-mini', provider: 'openai', status: 'error',
                                                 error: @certification_failure)
              raise @certification_failure
            end

            status = @certification_result.is_a?(Hash) && @certification_result[:error] ? 'error' : 'ok'
            Llm::UsageContext.record_operation(model: 'gpt-5-mini', provider: 'openai', status: status)
            @certification_result
          end

          define_method(:event_name) { feature }
          define_method(:llm_credential) { { api_key: 'stubbed-key', source: :system } }
        end
      end
      let(:service) { service_class.new(account: account, result: { message: 'ok' }) }
      let(:counts_toward_usage) { service.send(:counts_toward_usage?) }

      before do
        account.plan.update!(monthly_messages: 1) if usage_config[:bucket] == :captain_responses
        account.enable_features!('captain_integration')
      end

      it "applies the mapped usage bucket on success for #{service_name}" do
        expected_delta = counts_toward_usage ? 1 : 0
        expect { service.perform }.to change { account.reload.current_usage_period.public_send(usage_config[:counter_column]) }
          .by(expected_delta)
        expect(account.current_usage_period.ai_usage_reservations.where(released_at: nil)).to be_empty
        expect(AiUsageEvent.where(account_id: account.id, feature: usage_config[:feature], status: 'ok')).to exist
      end

      it "releases the receipt and records a provider error for #{service_name}" do
        failed = service_class.new(account: account, result: { error: 'provider failed' })

        expect { failed.perform }.not_to(change { account.reload.current_usage_period.public_send(usage_config[:counter_column]) })
        receipts = account.current_usage_period.ai_usage_reservations
        expect(receipts.where.not(released_at: nil)).to exist if counts_toward_usage
        expect(receipts.where(released_at: nil)).to be_empty
        expect(AiUsageEvent.where(account_id: account.id, feature: usage_config[:feature], status: 'error')).to exist
      end

      it "releases the receipt after an exception for #{service_name}" do
        failed = service_class.new(account: account, failure: Timeout::Error.new('provider timeout'))

        expect { failed.perform }.to raise_error(Timeout::Error)
        expect(account.reload.current_usage_period.public_send(usage_config[:counter_column])).to eq(0)
        receipts = account.current_usage_period.ai_usage_reservations
        expect(receipts.where.not(released_at: nil)).to exist if counts_toward_usage
        expect(receipts.where(released_at: nil)).to be_empty
        expect(AiUsageEvent.where(account_id: account.id, feature: usage_config[:feature], status: 'error')).to exist
      end

      it "treats an empty response as a failed task for #{service_name}" do
        empty = service_class.new(account: account, result: nil)

        expect { empty.perform }.not_to(change { account.reload.current_usage_period.public_send(usage_config[:counter_column]) })
        receipts = account.current_usage_period.ai_usage_reservations
        expect(receipts.where.not(released_at: nil)).to exist if counts_toward_usage
        expect(receipts.where(released_at: nil)).to be_empty
      end

      it "blocks without a provider call when exhausted for #{service_name}" do
        account.current_usage_period.update!(usage_config[:counter_column] => 1)

        result = service.perform
        if counts_toward_usage
          expect(result).to include(error_code: 429)
          expect(AiUsageEvent.where(account_id: account.id)).to be_empty
        else
          expect(result).to include(message: 'ok')
          expect(AiUsageEvent.where(account_id: account.id, feature: usage_config[:feature], status: 'ok')).to exist
        end
      end

      it "blocks before the provider when the required feature is disabled for #{service_name}" do
        account.disable_features!(usage_config[:required_gate])

        expect(service.perform).to include(error: I18n.t('captain.disabled'))
        expect(account.reload.current_usage_period.public_send(usage_config[:counter_column])).to eq(0)
        expect(AiUsageEvent.where(account_id: account.id)).to be_empty
      end

      it "treats a NULL internal allowance as unlimited for #{service_name}" do
        if usage_config[:bucket] == :internal && counts_toward_usage
          account.plan.update!(captain_internal_calls: nil)

          expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
          expect(account.current_usage_period.ai_usage_reservations.where(released_at: nil)).to be_empty
          expect(AiUsageEvent.where(account_id: account.id, feature: usage_config[:feature], status: 'ok')).to exist
        elsif usage_config[:bucket] != :internal
          expect(usage_config[:bucket]).to eq(:captain_responses)
        end
      end

      it "releases then charges once on retry for #{service_name}" do
        failed = service_class.new(account: account, result: { error: 'provider failed' })
        failed.perform

        delta = counts_toward_usage ? 1 : 0
        expect { service.perform }.to change { account.reload.current_usage_period.public_send(usage_config[:counter_column]) }.by(delta)
        expect(account.current_usage_period.ai_usage_reservations.where(released_at: nil)).to be_empty
      end
    end

    Captain::BaseTaskService.descendants.sort_by(&:name).each do |service_class|
      it_behaves_like 'the Captain task reservation contract', service_class.name
    end

    it 'releases the internal receipt when CSAT rejects malformed JSON' do
      service = Captain::CsatUtilityAnalysisService.new(account: account, message: 'Thanks for your help')
      allow(service).to receive(:make_api_call).and_return(message: '{broken json')

      result = service.perform

      expect(result).to include(error: 'Invalid LLM response format')
      expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
      expect(account.current_usage_period.ai_usage_reservations.where.not(released_at: nil)).to exist
    end

    it 'uses Ruby JSON parsing semantics for duplicate CSAT fields and consumes the receipt' do
      service = Captain::CsatUtilityAnalysisService.new(account: account, message: 'Thanks for your help')
      allow(service).to receive(:make_api_call).and_return(
        message: '{"classification":"LIKELY_MARKETING","classification":"LIKELY_UTILITY",' \
                 '"optimized_message":"Thank you"}'
      )

      result = service.perform

      expect(result).to include(classification: 'LIKELY_UTILITY')
      expect(account.reload.current_usage_period.internal_calls_consumed).to eq(1)
      expect(account.current_usage_period.ai_usage_reservations).to be_empty
    end
  end
end
