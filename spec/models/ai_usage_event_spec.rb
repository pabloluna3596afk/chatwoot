require 'rails_helper'

RSpec.describe AiUsageEvent do
  describe 'instrumented feature bucket mapping' do
    it 'maps every feature emitted by instrumented Ruby call sites' do
      ruby_files = %w[app enterprise lib spec].flat_map do |directory|
        Dir.glob(Rails.root.join(directory, '**', '*.rb'))
      end
      source_features = ruby_files.flat_map do |path|
        source = File.read(path)
        source.scan(/feature_name:\s*['"]([^'"]+)['"]/).flatten +
          source.scan(/def (?:event_name|feature_name)\s+['"]([^'"]+)['"]/).flatten +
          source.scan(/Llm::UsageContext\.with\([\s\S]{0,500}?feature:\s*['"]([^'"]+)['"]/).flatten
      end
      source_features.concat(Integrations::LlmBaseService::ALLOWED_EVENT_NAMES)
      source_features.concat(Captain::RewriteService::ALLOWED_OPERATIONS.map(&:to_s))

      expect(source_features.uniq - Llm::UsageFeatureBuckets::FEATURE_BUCKETS.keys).to be_empty
      expect(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch('audio_transcription')).to eq(:captain_responses)
      expect(Llm::UsageFeatureBuckets::FEATURE_BUCKETS.fetch('assistant_playground')).to eq(:captain_responses)
    end

    it 'fails loudly when a feature has not been assigned a bucket' do
      expect { Llm::UsageContext.send(:bucket_for, 'new_unmapped_feature') }
        .to raise_error(ArgumentError, 'Unmapped AI usage feature: new_unmapped_feature')
    end
  end

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
        def generate_once(**)
          response
        end
      end
      chat = chat_class.new(model, response)
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :copilot, feature: 'copilot_reply', usage_group_id: group_id) do
        3.times { chat.generate_once }
      end

      expect(described_class.where(usage_group_id: group_id).count).to eq(3)
      expect(described_class.where(usage_group_id: group_id).pluck(:bucket).uniq).to eq(['copilot'])
    end

    it 'records provider failures with status and error class' do
      account = create(:account)
      chat_class = Class.new(Struct.new(:model)) do
        def generate_once(**)
          raise Timeout::Error
        end
      end
      chat = chat_class.new(Struct.new(:id, :provider).new('gpt-6-luna', 'openai'))
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      group_id = SecureRandom.uuid

      Llm::UsageContext.with(account: account, bucket: :internal, feature: 'summary', usage_group_id: group_id) do
        expect { chat.generate_once }.to raise_error(Timeout::Error)
      end

      event = described_class.find_by!(usage_group_id: group_id)
      expect(event).to have_attributes(status: 'error', error_class: 'Timeout::Error')
      expect(event.latency_ms).to be >= 0
    end

    it 'keeps a successful provider response when writing the event fails' do
      account = create(:account)
      response = Struct.new(:tokens).new(Struct.new(:input, :output, :cached_input, :reasoning).new(5, 2, 0, 0))
      chat_class = Class.new(Struct.new(:model, :response)) do
        def generate_once(**)
          response
        end
      end
      chat = chat_class.new(Struct.new(:id, :provider).new('gpt-6-luna', 'openai'), response)
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      allow(Llm::UsageContext).to receive(:record_event).and_raise(ActiveRecord::ConnectionNotEstablished)

      result = Llm::UsageContext.with(account: account, bucket: :copilot, feature: 'copilot_reply') do
        chat.generate_once
      end

      expect(result).to equal(response)
    end

    it 'keeps the original provider exception when event recording also fails' do
      account = create(:account)
      provider_error = Timeout::Error.new('provider timed out')
      chat_class = Class.new(Struct.new(:model)) do
        attr_accessor :provider_error

        def generate_once(**)
          raise provider_error
        end
      end
      chat = chat_class.new(Struct.new(:id, :provider).new('gpt-6-luna', 'openai'))
      chat.provider_error = provider_error
      chat.singleton_class.prepend(Llm::Config::UsageRecordingChat)
      allow(Llm::UsageContext).to receive(:record_event).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect do
        Llm::UsageContext.with(account: account, bucket: :copilot, feature: 'copilot_reply') do
          chat.generate_once
        end
      end.to(raise_error { |error| expect(error).to equal(provider_error) })
    end

    it 'records prompt and completion token usage from a direct OpenAI response' do
      account = create(:account)
      AiModelPrice.create!(model: 'gpt-6-luna', input_per_million: 0.10,
                           cached_input_per_million: 0.02, output_per_million: 0.50,
                           effective_from: 1.day.ago)
      group_id = SecureRandom.uuid
      response = {
        usage: {
          prompt_tokens: 100, prompt_tokens_details: { cached_tokens: 25 },
          completion_tokens: 10, completion_tokens_details: { reasoning_tokens: 4 }
        }
      }

      Llm::UsageContext.with(account: account, bucket: :captain_responses, feature: 'paginated_faq_generation',
                             usage_group_id: group_id) do
        Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', response: response, status: 'ok')
      end

      event = described_class.find_by!(usage_group_id: group_id)
      expect(event).to have_attributes(input_tokens: 100, cached_input_tokens: 25, output_tokens: 10, reasoning_tokens: 4)
      expect(event.cost_usd).to eq(BigDecimal('0.000013'))
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
