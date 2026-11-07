require 'rails_helper'

RSpec.describe Llm::LegacyBaseOpenAiService do
  let(:service) { described_class.allocate }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    service.instance_variable_set(:@client, openai_client)
  end

  describe '#chat' do
    it 'sends the configured reasoning effort for gpt-6-luna' do
      expect(openai_client).to receive(:chat).with(
        parameters: { model: 'gpt-6-luna', reasoning_effort: 'none' }
      )

      service.send(:chat, parameters: { model: 'gpt-6-luna' })
    end

    it 'omits reasoning effort for models without a configured value' do
      expect(openai_client).to receive(:chat).with(parameters: { model: 'gpt-5.2' })

      service.send(:chat, parameters: { model: 'gpt-5.2' })
    end

    it 'preserves a caller supplied reasoning effort' do
      expect(openai_client).to receive(:chat).with(
        parameters: { model: 'gpt-6-luna', reasoning_effort: 'high' }
      )

      service.send(:chat, parameters: { model: 'gpt-6-luna', reasoning_effort: 'high' })
    end
  end
end
