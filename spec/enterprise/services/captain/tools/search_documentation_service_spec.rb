require 'rails_helper'

RSpec.describe Captain::Tools::SearchDocumentationService do
  let(:assistant) { create(:captain_assistant) }
  let(:service) { described_class.new(assistant) }
  let(:question) { 'How to create a new account?' }
  let(:answer) { 'You can create a new account by clicking on the Sign Up button.' }
  let(:external_link) { 'https://example.com/docs/create-account' }

  describe '#name' do
    it 'returns the correct service name' do
      expect(service.name).to eq('search_documentation')
    end
  end

  describe '#description' do
    it 'returns the service description' do
      expect(service.description).to eq('Search and retrieve documentation from knowledge base')
    end
  end

  describe '#parameters_schema' do
    it 'defines query parameter' do
      expect(service.parameters_schema.fetch('properties').keys).to contain_exactly('query')
    end
  end

  describe '#execute' do
    let!(:response) do
      create(
        :captain_assistant_response,
        assistant: assistant,
        question: question,
        answer: answer,
        status: 'approved'
      )
    end

    let(:documentable) { create(:captain_document, external_link: external_link) }

    context 'when matching responses exist' do
      before do
        response.update(documentable: documentable)
        allow(Captain::AssistantResponse).to receive(:search).with(question).and_return([response])
      end

      it 'returns formatted responses for the search query' do
        result = service.execute(query: question)

        expect(result).to include(question)
        expect(result).to include(answer)
        expect(result).to include(external_link)
      end
    end

    context 'when no matching responses exist' do
      before do
        allow(Captain::AssistantResponse).to receive(:search).with(question).and_return([])
      end

      it 'returns an empty string' do
        expect(service.execute(query: question)).to eq('No FAQs found for the given query')
      end

      it 'logs only the query length' do
        private_query = 'customer@example.invalid asks for account deletion'
        translator = instance_double(Captain::Llm::TranslateQueryService, translate: private_query)
        allow(Captain::Llm::TranslateQueryService).to receive(:new).and_return(translator)
        approved_responses = assistant.responses.approved
        allow(approved_responses).to receive(:search).with(private_query).and_return([])
        allow(assistant.responses).to receive(:approved).and_return(approved_responses)
        log_messages = []
        allow(Rails.logger).to receive(:info) do |message = nil, &block|
          log_messages << (block ? block.call : message)
        end

        service.execute(query: private_query)

        expect(log_messages.join).to include("query_length=#{private_query.length}")
        expect(log_messages.join).not_to include(private_query, 'customer@example.invalid')
      end
    end
  end

  describe 'SearchReplyDocumentationService logging' do
    it 'logs query length without query text' do
      private_query = 'SECRETO-XYZ-123'
      reply_service = Captain::Tools::SearchReplyDocumentationService.new(account: assistant.account, assistant: assistant)
      translator = instance_double(Captain::Llm::TranslateQueryService, translate: private_query)
      approved_responses = assistant.responses.approved
      allow(Captain::Llm::TranslateQueryService).to receive(:new).and_return(translator)
      allow(approved_responses).to receive(:search).with(private_query, account_id: assistant.account.id).and_return([])
      allow(assistant.responses).to receive(:approved).and_return(approved_responses)
      log_messages = []
      allow(Rails.logger).to receive(:info) do |message = nil, &block|
        log_messages << (block ? block.call : message)
      end

      reply_service.method(:execute).super_method.call(query: private_query)

      expect(log_messages.join).to include("query_length=#{private_query.length}")
      expect(log_messages.join).not_to include(private_query)
    end
  end
end
