require 'rails_helper'

RSpec.describe Captain::Llm::FaqGeneratorService do
  let(:content) { 'Sample content for FAQ generation' }
  let(:document) { create(:captain_document, content: content) }
  let(:service) { described_class.new(document: document) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:sample_faqs) do
    [
      { 'question' => 'What is this service?', 'answer' => 'It generates FAQs.' },
      { 'question' => 'How does it work?', 'answer' => 'Using AI technology.' }
    ]
  end
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: { faqs: sample_faqs }.to_json)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_thinking).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_provider_options).and_return(mock_chat)
    allow(mock_chat).to receive(:add_message).with(role: :user, content: 'Respond with valid JSON.')
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#generate' do
    context 'when successful' do
      it 'uses the document FAQ generation feature model' do
        expect(RubyLLM).to receive(:chat).with(
          model: Llm::Models.default_model_for('document_faq_generation'), protocol: :responses
        ).and_return(mock_chat)

        described_class.new(document: document).generate
      end

      it 'resolves the feature model from the document account' do
        expect(Llm::FeatureRouter).to receive(:resolve).with(
          feature: 'document_faq_generation',
          account: document.account
        ).and_call_original

        described_class.new(document: document).generate
      end

      it 'returns parsed FAQs from the LLM response' do
        result = service.generate
        expect(result).to eq(sample_faqs)
      end

      it 'sends content to LLM with JSON response format' do
        expect(mock_chat).to receive(:with_provider_options).with({ text: { format: { type: 'json_object' } } }).and_return(mock_chat)
        service.generate
      end

      it 'uses SystemPromptsService with the account language' do
        account_language = document.account.locale_english_name
        expect(Captain::Llm::SystemPromptsService).to receive(:faq_generator).with(account_language).at_least(:once).and_call_original
        service.generate
      end
    end

    context 'with different language' do
      before { allow(document.account).to receive(:locale_english_name).and_return('spanish') }

      it 'passes the correct language to SystemPromptsService' do
        expect(Captain::Llm::SystemPromptsService).to receive(:faq_generator).with('spanish').at_least(:once).and_call_original
        service.generate
      end
    end

    context 'when LLM API fails' do
      before do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new('API Error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs and raises so the job can retry' do
        expect(Rails.logger).to receive(:error).with('LLM API Error: API Error')
        expect { service.generate }.to raise_error(RubyLLM::Error)
      end
    end

    context 'when response content is nil' do
      let(:nil_response) { instance_double(RubyLLM::Message, content: nil) }

      before do
        allow(mock_chat).to receive(:ask).and_return(nil_response)
      end

      it 'returns empty array' do
        expect(service.generate).to eq([])
      end
    end

    context 'when JSON parsing fails' do
      let(:invalid_response) { instance_double(RubyLLM::Message, content: 'invalid json') }

      before do
        allow(mock_chat).to receive(:ask).and_return(invalid_response)
      end

      it 'logs error and returns empty array' do
        expect(Rails.logger).to receive(:error).with(/Error in parsing GPT processed response:/)
        expect(service.generate).to eq([])
      end
    end

    context 'when response is missing faqs key' do
      let(:missing_key_response) { instance_double(RubyLLM::Message, content: '{"data": []}') }

      before do
        allow(mock_chat).to receive(:ask).and_return(missing_key_response)
      end

      it 'returns empty array via KeyError rescue' do
        expect(service.generate).to eq([])
      end
    end
  end

  describe 'internal knowledge quota' do
    it 'charges by each started 50000 characters with a minimum of two units' do
      put_account_on_plan(document.account, captain_internal_calls: 20)
      [1, 50_000, 50_001].each do |characters|
        document.update!(content: 'a' * characters)
        described_class.new(document: document).generate
      end

      expect(document.account.reload.current_usage_period.internal_calls_consumed).to eq(8)
      expect(document.account.current_usage_period.responses_consumed).to eq(0)
    end

    it 'does not call the provider when the text estimate exceeds the remaining quota' do
      put_account_on_plan(document.account, captain_internal_calls: 3)
      document.update!(content: 'a' * 50_001)
      expect(mock_chat).not_to receive(:ask)

      expect { described_class.new(document: document).generate }.to raise_error(Llm::KnowledgeUsage::QuotaExceeded)
      expect(document.account.reload.current_usage_period.internal_calls_consumed).to eq(0)
    end

    it 'releases the text reservation after a provider error' do
      put_account_on_plan(document.account, captain_internal_calls: 2)
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new('API Error'))

      expect { service.generate }.to raise_error(RubyLLM::Error)
      expect(document.account.reload.current_usage_period.internal_calls_consumed).to eq(0)
      expect(AiUsageReservation.where(account_plan_usage: document.account.current_usage_period).where.not(released_at: nil).count).to eq(1)
    end

    it 'charges changed URL content again, but skips an unchanged fingerprint and a completed job retry' do
      put_account_on_plan(document.account, captain_internal_calls: 10)
      document.update!(status: :available)
      allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(
        instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
      )
      Captain::Documents::ResponseBuilderJob.perform_now(document)
      fetcher = instance_double(Captain::Documents::SinglePageFetcher)
      allow(Captain::Documents::SinglePageFetcher).to receive(:new).and_return(fetcher)
      result = Captain::Documents::SinglePageFetcher::Result.new(success: true, title: 'Updated', content: 'Changed content')
      allow(fetcher).to receive(:fetch).and_return(result)
      sync = Captain::Documents::SyncService.new(document)

      sync.perform
      Captain::Documents::ResponseBuilderJob.perform_now(document)
      expect(sync.perform).to eq(:unchanged)
      Captain::Documents::ResponseBuilderJob.perform_now(document)

      expect(document.account.reload.current_usage_period.internal_calls_consumed).to eq(4)
      expect(mock_chat).to have_received(:ask).twice
    end
  end
end
