require 'rails_helper'

RSpec.describe Llm::Config do
  let(:agents_config) do
    Struct.new(:openai_api_key, :openai_api_base, :default_model, :openai_protocol, :model_registry_file, :debug).new
  end
  let(:ruby_llm_config) { Struct.new(:openai_api_key, :openai_api_base, :openai_protocol, :model_registry_file, :logger).new }

  before do
    InstallationConfig.where(name: described_class::SETTING_NAMES).destroy_all
    described_class.reset!
    allow(RubyLLM).to receive(:configure).and_yield(ruby_llm_config)
    allow(Agents).to receive(:configure).and_yield(agents_config)
  end

  after { described_class.reset! }

  def save_setting(name, value)
    InstallationConfig.find_or_initialize_by(name: name).update!(value: value)
  end

  describe '.api_key_configured?' do
    it 'is false without the installation key' do
      expect(described_class.api_key_configured?).to be(false)
    end

    it 'is false for a blank key' do
      save_setting('CAPTAIN_OPEN_AI_API_KEY', '')

      expect(described_class.api_key_configured?).to be(false)
    end

    it 'is true once the key is saved, without any restart' do
      expect(described_class.api_key_configured?).to be(false)

      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-test')

      expect(described_class.api_key_configured?).to be(true)
    end
  end

  describe '.standard_openai_endpoint?' do
    it 'accepts the default OpenAI endpoint' do
      save_setting('CAPTAIN_OPEN_AI_ENDPOINT', 'https://api.openai.com/')

      expect(described_class.standard_openai_endpoint?).to be(true)
    end

    it 'rejects a custom endpoint' do
      save_setting('CAPTAIN_OPEN_AI_ENDPOINT', 'https://azure.example.test/openai')

      expect(described_class.standard_openai_endpoint?).to be(false)
    end
  end

  describe '.with_api_key' do
    it 'provides request credentials through an isolated RubyLLM context' do
      global_key = RubyLLM.config.openai_api_key

      described_class.with_api_key('account-key', api_base: 'https://llm.example.test/v1') do |context|
        expect(context.config.openai_api_key).to eq('account-key')
        expect(context.config.openai_api_base).to eq('https://llm.example.test/v1')
      end

      expect(RubyLLM.config.openai_api_key).to eq(global_key)
    end
  end

  describe '.with_chat_context' do
    it 'supplies account credentials to both direct SDK and RubyLLM chat constructors without changing globals' do
      global_key = RubyLLM.config.openai_api_key
      described_class.with_chat_context('account-key') do
        sdk_chat = RubyLLM::Chat.new(model: 'gpt-5.2')
        legacy_chat = RubyLLM.chat(model: 'gpt-5.2')
        expect(sdk_chat.instance_variable_get(:@config).openai_api_key).to eq('account-key')
        expect(legacy_chat.instance_variable_get(:@config).openai_api_key).to eq('account-key')
        expect(sdk_chat.instance_variable_get(:@config).openai_api_base).to eq("#{LlmConstants::OPENAI_API_ENDPOINT.chomp('/')}/v1")
        expect(Thread.new { ActiveSupport::IsolatedExecutionState[:llm_chat_context] }.value).to be_nil
      end
      expect(RubyLLM.config.openai_api_key).to eq(global_key)
      expect(ActiveSupport::IsolatedExecutionState[:llm_chat_context]).to be_nil
    end

    it 'restores the previous context after nested calls and exceptions' do
      described_class.with_chat_context('outer-key') do
        outer = ActiveSupport::IsolatedExecutionState[:llm_chat_context]
        expect { described_class.with_chat_context('inner-key') { raise 'model failed' } }.to raise_error('model failed')
        expect(ActiveSupport::IsolatedExecutionState[:llm_chat_context]).to equal(outer)
      end
      expect(ActiveSupport::IsolatedExecutionState[:llm_chat_context]).to be_nil
    end
  end

  describe '.refresh!' do
    it 'configures both SDKs for chat completions while there is no installation key' do
      described_class.refresh!

      expect(RubyLLM).to have_received(:configure).once
      expect(Agents).to have_received(:configure).once
      expect(ruby_llm_config).to have_attributes(openai_protocol: :chat_completions)
      expect(agents_config).to have_attributes(
        openai_protocol: :chat_completions,
        default_model: LlmConstants::DEFAULT_MODEL,
        debug: false
      )
    end

    it 'applies a key saved after the first refresh' do
      described_class.refresh!
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-new')
      described_class.refresh!

      expect(Agents).to have_received(:configure).twice
      expect(agents_config).to have_attributes(
        openai_api_key: 'sk-new', default_model: LlmConstants::DEFAULT_MODEL, debug: false, openai_protocol: :chat_completions
      )
      expect(RubyLLM).to have_received(:configure).twice
    end

    it 'does not reapply while the settings are unchanged' do
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-test')

      3.times { described_class.refresh! }

      expect(Agents).to have_received(:configure).once
      expect(RubyLLM).to have_received(:configure).once
    end

    it 'reapplies when the key, the model or the endpoint change' do
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-one')
      described_class.refresh!

      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-two')
      described_class.refresh!
      save_setting('CAPTAIN_OPEN_AI_MODEL', 'gpt-5-mini')
      described_class.refresh!
      save_setting('CAPTAIN_OPEN_AI_ENDPOINT', 'https://llm.example.test/')
      described_class.refresh!

      expect(Agents).to have_received(:configure).exactly(4).times
      expect(agents_config).to have_attributes(
        openai_api_key: 'sk-two', default_model: 'gpt-5-mini', openai_api_base: 'https://llm.example.test/v1',
        openai_protocol: :chat_completions
      )
    end

    it 'is what initialize! does' do
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-test')

      described_class.initialize!

      expect(described_class).to be_initialized
      expect(Agents).to have_received(:configure).once
    end
  end

  describe 'pinned reasoning effort' do
    around { |example| described_class.with_chat_context('test-key') { example.run } }

    it 'sends the effort declared in llm.yml and keeps it when other provider options are set' do
      chat = RubyLLM.chat(model: 'gpt-6-luna')
      expect(chat.instance_variable_get(:@provider_options)).to eq(reasoning_effort: 'none')

      chat.with_provider_options(response_format: { type: 'json_object' })
      expect(chat.instance_variable_get(:@provider_options)).to eq(reasoning_effort: 'none', response_format: { type: 'json_object' })
    end

    it 'adds nothing for models without a pinned effort' do
      chat = RubyLLM.chat(model: 'gpt-5.2')

      expect(chat.instance_variable_get(:@provider_options)).to eq({})
    end
  end
end
