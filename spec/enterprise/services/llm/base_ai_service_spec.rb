require 'rails_helper'

RSpec.describe Llm::BaseAiService do
  subject(:service) { described_class.new }

  let(:account) { create(:account) }

  before do
    InstallationConfig.where(name: %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL]).destroy_all
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
  end

  describe '#initialize' do
    it 'uses the installation model when no feature is provided' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.2')

      expect(described_class.new.model).to eq('gpt-5.2')
    end

    it 'uses the account override when feature context is provided' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.2')
      account.update!(captain_models: { 'assistant' => 'gpt-5.2' })

      expect(described_class.new(feature: 'assistant', account: account).model).to eq('gpt-5.2')
    end

    it 'uses the installation model when feature context has no account override' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.2')

      expect(described_class.new(feature: 'assistant', account: account).model).to eq('gpt-5.2')
    end

    it 'uses the Captain V2 assistant default ahead of the installation model' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.2')
      account.enable_features!('captain_integration_v2')

      expect(described_class.new(feature: 'assistant', account: account).model).to eq('gpt-6-luna')
      expect(account.reload.captain_models).to be_nil
    end

    it 'uses the feature default when feature context has no account override or installation model' do
      expect(described_class.new(feature: 'assistant', account: account).model).to eq(Llm::Models.default_model_for('assistant'))
    end
  end

  describe '#sanitize_json_response' do
    it 'strips ```json fences' do
      input = "```json\n{\"key\": \"value\"}\n```"
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'strips bare ``` fences' do
      input = "```\n{\"key\": \"value\"}\n```"
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'passes through plain JSON unchanged' do
      input = '{"key": "value"}'
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'returns nil for nil input' do
      expect(service.send(:sanitize_json_response, nil)).to be_nil
    end

    it 'strips surrounding whitespace' do
      input = "  \n{\"key\": \"value\"}\n  "
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end
  end

  describe '#chat' do
    let(:mock_chat) { instance_double(RubyLLM::Chat) }

    before do
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:with_thinking).and_return(mock_chat)
      allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    end

    it 'uses Responses with the configured assistant reasoning effort' do
      service = described_class.new(feature: 'assistant', account: account)

      expect(RubyLLM).to receive(:chat).with(model: 'gpt-6-luna', protocol: :responses).and_return(mock_chat)
      expect(mock_chat).to receive(:with_thinking).with(effort: :none).and_return(mock_chat)

      service.chat
    end
  end

  describe '#json_chat' do
    let(:mock_chat) { instance_double(RubyLLM::Chat) }

    before do
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:with_thinking).and_return(mock_chat)
      allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
      allow(mock_chat).to receive(:add_message).and_return(mock_chat)
      allow(mock_chat).to receive(:with_provider_options).and_return(mock_chat)
    end

    it 'adds JSON mode and a JSON instruction for Responses requests' do
      service = described_class.new(feature: 'assistant', account: account)

      expect(mock_chat).to receive(:add_message).with(role: :user, content: 'Respond with valid JSON.').and_return(mock_chat)
      expect(mock_chat).to receive(:with_provider_options).with({ text: { format: { type: 'json_object' } } }).and_return(mock_chat)

      service.json_chat
    end
  end
end
