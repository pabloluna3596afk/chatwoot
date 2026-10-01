require 'rails_helper'

RSpec.describe Llm::Config do
  let(:agents_config) { Struct.new(:openai_api_key, :openai_api_base, :default_model, :debug).new }

  before do
    InstallationConfig.where(name: described_class::SETTING_NAMES).destroy_all
    described_class.reset!
    allow(RubyLLM).to receive(:configure)
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

  describe '.refresh!' do
    it 'configures RubyLLM but not the Agents SDK while there is no key' do
      described_class.refresh!

      expect(RubyLLM).to have_received(:configure).once
      expect(Agents).not_to have_received(:configure)
    end

    it 'applies a key saved after the first refresh' do
      described_class.refresh!
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-new')
      described_class.refresh!

      expect(Agents).to have_received(:configure).once
      expect(agents_config).to have_attributes(openai_api_key: 'sk-new', default_model: LlmConstants::DEFAULT_MODEL, debug: false)
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
        openai_api_key: 'sk-two', default_model: 'gpt-5-mini', openai_api_base: 'https://llm.example.test/v1'
      )
    end

    it 'is what initialize! does' do
      save_setting('CAPTAIN_OPEN_AI_API_KEY', 'sk-test')

      described_class.initialize!

      expect(described_class).to be_initialized
      expect(Agents).to have_received(:configure).once
    end
  end
end
