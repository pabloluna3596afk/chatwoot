require 'rails_helper'

RSpec.describe AiUsageEvent do
  describe '.calculate_cost' do
    it 'uses the active price and separates cached input tokens' do
      AiModelPrice.create!(model: 'gpt-6-luna', input_per_million: 0.10,
                           cached_input_per_million: 0.02, output_per_million: 0.50,
                           effective_from: 1.day.ago)

      cost = described_class.calculate_cost(
        model: 'gpt-6-luna', input_tokens: 1_000_000,
        cached_input_tokens: 200_000, output_tokens: 100_000
      )

      expect(cost).to eq(BigDecimal('0.134'))
    end
  end

  describe 'recording a usage group' do
    it 'records each call under one isolated message group' do
      account = create(:account)
      model = Struct.new(:id, :provider).new('gpt-6-luna', 'openai')
      tokens = Struct.new(:input, :output, :cached_input, :reasoning).new(100, 20, 0, 4)
      response = Struct.new(:tokens).new(tokens)
      chat_class = Class.new(Struct.new(:model, :response)) do
        def ask(*)
          response
        end
      end
      chat = chat_class.new(model, response)
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :copilot, feature: 'copilot_reply', usage_group_id: group_id) do
        3.times { chat.ask('reply') }
      end

      expect(described_class.where(usage_group_id: group_id).count).to eq(3)
      expect(described_class.where(usage_group_id: group_id).pluck(:bucket).uniq).to eq(['copilot'])
    end

    it 'records provider failures with status and error class' do
      account = create(:account)
      chat_class = Class.new(Struct.new(:model)) do
        def ask(*)
          raise Timeout::Error
        end
      end
      chat = chat_class.new(Struct.new(:id, :provider).new('gpt-6-luna', 'openai'))
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :internal, feature: 'summary', usage_group_id: group_id) do
        expect { chat.ask('summarize') }.to raise_error(Timeout::Error)
      end

      event = described_class.find_by!(usage_group_id: group_id)
      expect(event).to have_attributes(status: 'error', error_class: 'Timeout::Error')
      expect(event.latency_ms).to be >= 0
    end

    it 'records token usage from non-chat RubyLLM operations' do
      account = create(:account)
      tokens = Struct.new(:input, :output, :cached_input, :reasoning).new(250, 0, 0, 0)
      response = Struct.new(:model, :tokens).new('text-embedding-3-small', tokens)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :internal, feature: 'embedding', usage_group_id: group_id) do
        Llm::UsageContext.record_operation(
          model: response.model, provider: 'openai', response: response, status: 'ok'
        )
      end

      event = described_class.find_by!(usage_group_id: group_id)
      expect(event).to have_attributes(bucket: 'internal', input_tokens: 250, output_tokens: 0)
    end

    it 'stores the event cost without changing it when a later price takes effect' do
      account = create(:account)
      price = AiModelPrice.create!(model: 'gpt-6-luna', input_per_million: 0.10,
                                   cached_input_per_million: 0.10, output_per_million: 0.50,
                                   effective_from: 1.day.ago)
      chat = Struct.new(:model).new(Struct.new(:id, :provider).new('gpt-6-luna', 'openai'))
      tokens = Struct.new(:input, :output, :cached_input, :reasoning).new(1_000_000, 1_000_000, 0, 0)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :captain_responses, feature: 'captain_reply', usage_group_id: group_id) do
        Llm::UsageContext.record(chat: chat, response: Struct.new(:tokens).new(tokens), status: 'ok')
      end
      event = described_class.find_by!(usage_group_id: group_id)
      AiModelPrice.create!(model: price.model, input_per_million: 2, cached_input_per_million: 2,
                           output_per_million: 5, effective_from: 1.day.from_now)

      expect(event.reload.cost_usd).to eq(BigDecimal('0.6'))
    end
  end
end
