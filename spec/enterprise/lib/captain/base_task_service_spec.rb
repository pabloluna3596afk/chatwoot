require 'rails_helper'

RSpec.describe Captain::BaseTaskService, type: :model do
  let(:account) { create(:account) }

  before { put_account_on_plan(account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:perform_result) { { message: 'Test response' } }
  let(:perform_error) { nil }
  let(:exhausted_usage_limits) do
    {
      agents: ChatwootApp.max_limit,
      inboxes: ChatwootApp.max_limit,
      captain: { internal: { total_count: 0, current_available: 0 } }
    }
  end

  # Create a concrete test service class with enterprise module prepended
  let(:test_service_class) do
    result = perform_result
    error = perform_error
    klass = Class.new(described_class) do
      define_method(:perform) do
        raise error if error

        result
      end

      def event_name
        'follow_up'
      end
    end
    # Manually prepend enterprise module to test class
    klass.prepend(Enterprise::Captain::BaseTaskService)
    klass
  end

  let(:service) { test_service_class.new(account: account, conversation_display_id: conversation.display_id) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
  end

  describe '#perform with enterprise usage tracking' do
    # Ensure captain is enabled by default for tests unless explicitly testing disabled state
    before do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
      allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    end

    context 'when usage limit is exceeded' do
      before do
        account.plan.update!(captain_internal_calls: 1)
        account.current_usage_period.update!(internal_calls_consumed: 1)
      end

      it 'returns usage limit exceeded error' do
        result = service.perform
        expect(result[:error]).to eq(I18n.t('captain.internal_limit'))
        expect(result[:error_code]).to eq(429)
      end

      it 'does not increment usage' do
        expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
      end
    end

    it 'does not charge an internal pool until the plan configures an internal limit' do
      expect { service.perform }.not_to(change { account.current_usage_period&.internal_calls_consumed })
    end

    it 'reserves internal usage before executing when a limit is configured' do
      account.plan.update!(captain_internal_calls: 1)
      expect { service.perform }.to change { (account.reload.current_usage_period.internal_calls_consumed) }.by(1)
    end

    context 'when the provider call returns an error' do
      let(:perform_result) { { error: 'API Error' } }

      it 'releases the reservation when the provider returns an error' do
        account.plan.update!(captain_internal_calls: 1)

        expect { service.perform }.not_to change { account.reload.current_usage_period.internal_calls_consumed }
      end
    end

    it 'charges once when a retry succeeds after a returned error' do
      account.plan.update!(captain_internal_calls: 1)
      perform_result.replace(error: 'temporary provider error')

      expect(service.perform).to include(error: 'temporary provider error')
      perform_result.replace(message: 'recovered')

      expect { service.perform }.to change { account.reload.current_usage_period.internal_calls_consumed }.by(1)
    end

    context 'when the task raises after reserving' do
      let(:perform_error) { Timeout::Error.new }

      it 'releases the reservation and propagates the exception' do
        account.plan.update!(captain_internal_calls: 1)

        expect { service.perform }.to raise_error(Timeout::Error)
        expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
      end
    end

    context 'when account has its own OpenAI hook key' do
      before do
        create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'customer-own-key' })
      end

      it 'reserves internal usage for services that do not opt into BYOK' do
        account.plan.update!(captain_internal_calls: 1)

        expect { service.perform }.to change { (account.reload.current_usage_period.internal_calls_consumed) }.by(1)
      end

      context 'when the internal AI quota is exhausted on Cloud' do
        before do
          account.plan.update!(captain_internal_calls: 1)
          account.current_usage_period.update!(internal_calls_consumed: 1)
        end

        it 'returns usage limit exceeded error for services that do not opt into BYOK' do
          result = service.perform
          expect(result[:error]).to eq(I18n.t('captain.internal_limit'))
          expect(result[:error_code]).to eq(429)
        end
      end
    end

    context 'when subclass opts into account OpenAI hook usage' do
      let(:test_service_class) do
        result = perform_result
        klass = Class.new(described_class) do
          define_method(:perform) { result }
          define_method(:event_name) { 'follow_up' }
          define_method(:use_account_openai_hook?) { true }
        end
        klass.prepend(Enterprise::Captain::BaseTaskService)
        klass
      end

      before do
        create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'customer-own-key' })
      end

      it 'does not reserve usage when the subclass opts out' do
        expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
      end

      context 'when the captain_responses quota is exhausted on Cloud' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
          allow(account).to receive(:usage_limits).and_return(exhausted_usage_limits)
        end

        it 'bypasses the 429 gate and returns the underlying result' do
          result = service.perform
          expect(result).to eq(perform_result)
        end
      end
    end

    context 'when captain is disabled' do
      before do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)
      end

      context 'when on Chatwoot Cloud' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
        end

        it 'returns upgrade error message' do
          result = service.perform
          expect(result[:error]).to eq(I18n.t('captain.upgrade'))
        end

        it 'does not reserve usage' do
          expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
        end
      end

      context 'when self-hosted' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
        end

        it 'returns disabled error message' do
          result = service.perform
          expect(result[:error]).to eq(I18n.t('captain.disabled'))
        end

        it 'does not reserve usage' do
          expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
        end
      end
    end

    context 'when captain is enabled' do
      before do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
      end

      it 'proceeds with the task' do
        result = service.perform
        expect(result[:message]).to eq('Test response')
        expect(result[:error]).to be_nil
      end
    end

    context 'when subclass opts out via counts_toward_usage?' do
      let(:test_service_class) do
        result = perform_result
        klass = Class.new(described_class) do
          define_method(:perform) { result }
          define_method(:event_name) { 'follow_up' }
          define_method(:counts_toward_usage?) { false }
        end
        klass.prepend(Enterprise::Captain::BaseTaskService)
        klass
      end

      it 'does not reserve usage when the subclass opts out' do
        expect { service.perform }.not_to(change { account.reload.current_usage_period.internal_calls_consumed })
      end

      context 'when the captain_responses quota is exhausted on Cloud' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
          allow(account).to receive(:usage_limits).and_return(exhausted_usage_limits)
        end

        it 'bypasses the 429 gate and returns the underlying result' do
          result = service.perform
          expect(result).to eq(perform_result)
        end
      end
    end
  end
end
