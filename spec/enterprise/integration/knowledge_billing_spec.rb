require 'rails_helper'

RSpec.describe 'Knowledge billing', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:document) do
    create(:captain_document, account: account, assistant: assistant, external_link: 'PDF: billing-fixture',
                              openai_file_id: 'file-billing',
                              pdf_file: { io: StringIO.new('%PDF-1.4 simulated upload'), filename: 'billing.pdf', content_type: 'application/pdf' })
  end
  let(:client) { instance_double(OpenAI::Client) }
  let(:faqs) { [{ 'question' => 'What is billing?', 'answer' => 'Internal actions pay for knowledge generation.' }] }
  let(:last_chunk) do
    { 'choices' => [{ 'message' => { 'content' => { faqs: faqs, has_content: false }.to_json } }],
      'usage' => { 'prompt_tokens' => 100, 'completion_tokens' => 20 } }
  end
  let(:first_chunk) do
    { 'choices' => [{ 'message' => { 'content' => { faqs: faqs, has_content: true }.to_json } }] }
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Llm::FeatureRouter).to receive(:standard_openai_endpoint?).and_return(false)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(last_chunk)
    # Only provider output is simulated. Job, reservation, event and counter are real.
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(
      instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
    )
    allow(Captain::Llm::PdfProcessingService).to receive(:new).and_return(
      instance_double(Captain::Llm::PdfProcessingService, delete_openai_file: nil)
    )
  end

  [1, 10].each do |pages|
    it "charges two internal units for a final #{pages}-page PDF chunk and finishes the receipt" do
      put_account_on_plan(account, captain_internal_calls: 2)
      expect(account).to receive(:reserve_captain_ai_usage!).with(bucket: :internal, units: 2, reservation_id: anything).and_call_original
      expect(account).to receive(:finish_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_call_original

      Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: pages)

      expect(account.reload.current_usage_period.internal_calls_consumed).to eq(2)
      expect(AiUsageEvent.find_by!(account: account, feature: 'paginated_faq_generation')).to have_attributes(bucket: 'internal', units: 2)
      expect(AiUsageReservation.where(account_plan_usage: account.current_usage_period)).to be_empty
      expect(document.responses.count).to eq(1)
    end
  end

  it 'charges again after deleting and uploading the same source' do
    put_account_on_plan(account, captain_internal_calls: 4)
    Captain::Documents::ResponseBuilderJob.perform_now(document)
    document.destroy!
    second_document = create(:captain_document, account: account, assistant: assistant, external_link: 'PDF: billing-fixture',
                                                openai_file_id: 'file-billing',
                                                pdf_file: { io: StringIO.new('%PDF simulated'), filename: 'billing.pdf',
                                                            content_type: 'application/pdf' })

    Captain::Documents::ResponseBuilderJob.perform_now(second_document)

    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(4)
    expect(client).to have_received(:chat).twice
  end

  it 'rejects an insufficient quota without contacting the provider and leaves the document pending' do
    put_account_on_plan(account, captain_internal_calls: 1)
    expect(client).not_to receive(:chat)

    Captain::Documents::ResponseBuilderJob.perform_now(document)

    expect(document.reload).to have_attributes(status: 'in_progress', last_sync_error_code: 'usage_quota_exceeded')
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
    expect(AiUsageEvent.where(account: account)).to be_empty
  end

  it 'returns the quota-pending state through the real document API' do
    put_account_on_plan(account, captain_internal_calls: 1)
    agent = create(:user, account: account, role: :agent)
    Captain::Documents::ResponseBuilderJob.perform_now(document)

    get "/api/v1/accounts/#{account.id}/captain/documents", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload').find { |item| item['id'] == document.id }
    expect(payload).to include('status' => 'in_progress', 'last_sync_error_code' => 'usage_quota_exceeded', 'responses_count' => 0)
  end

  it 'keeps the first chunk FAQs when quota runs out before page eleven' do
    put_account_on_plan(account, captain_internal_calls: 2)
    allow(client).to receive(:chat).and_return(first_chunk, last_chunk)

    Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: 11)

    expect(document.reload).to have_attributes(status: 'in_progress', last_sync_error_code: 'usage_quota_exceeded')
    expect(document.responses.count).to eq(1)
    expect(document.metadata.dig('faq_generation', 'pages_processed')).to eq(10)
    expect(client).to have_received(:chat).once
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(2)
  end

  it 'charges four units for eleven pages with sufficient quota' do
    put_account_on_plan(account, captain_internal_calls: 4)
    allow(client).to receive(:chat).and_return(first_chunk, last_chunk)

    Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: 11)

    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(4)
    expect(document.reload.metadata.dig('faq_generation', 'pages_processed')).to eq(11)
    expect(client).to have_received(:chat).twice
  end

  it 'releases a failed chunk and retries from the saved page without charging the first chunk again' do
    put_account_on_plan(account, captain_internal_calls: 4)
    allow(client).to receive(:chat).and_return(first_chunk)
    Captain::Llm::PaginatedFaqGeneratorService.new(document, max_pages: 10).generate
    document.update!(metadata: document.metadata.deep_merge('faq_generation' => { 'completed' => false }))
    allow(client).to receive(:chat).and_raise(Faraday::ConnectionFailed, 'provider unavailable')

    expect { Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: 11) }.to raise_error(Faraday::ConnectionFailed)
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(2)
    expect(AiUsageReservation.where(account_plan_usage: account.current_usage_period).where.not(released_at: nil).count).to eq(1)
    allow(client).to receive(:chat).and_return(last_chunk)

    Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: 11)
    Captain::Documents::ResponseBuilderJob.perform_now(document, max_pages: 11)

    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(4)
    expect(client).to have_received(:chat).exactly(3).times
  end

  it 'continues to generate for an account without a plan or configured quota' do
    Captain::Documents::ResponseBuilderJob.perform_now(document)

    expect(document.responses.count).to eq(1)
    expect(client).to have_received(:chat).once
    expect(AiUsageEvent.find_by!(account: account, feature: 'paginated_faq_generation').units).to eq(2)
  end

  it 'stops at the configured page cap even if the provider keeps reporting more content' do
    allow(client).to receive(:chat).and_return(first_chunk)

    service = Captain::Llm::PaginatedFaqGeneratorService.new(document, max_pages: 1000)
    service.generate

    expect(service.total_pages_processed).to eq(Llm::UnitCosts.fetch(:pdf, :max_pages))
    expect(client).to have_received(:chat).exactly(Llm::UnitCosts.fetch(:pdf, :max_pages) / Llm::UnitCosts.fetch(:pdf, :pages_per_chunk)).times
  end

  it 'bounds the FAQ output before persisting or embedding it' do
    oversized_faqs = Array.new(Llm::UnitCosts.fetch(:max_faqs_per_document) + 1) do |index|
      { 'question' => index.to_s, 'answer' => 'Answer' }
    end
    response = { 'choices' => [{ 'message' => { 'content' => { faqs: oversized_faqs, has_content: false }.to_json } }] }
    allow(client).to receive(:chat).and_return(response)

    result = Captain::Llm::PaginatedFaqGeneratorService.new(document).generate

    expect(result.size).to eq(Llm::UnitCosts.fetch(:max_faqs_per_document))
    expect(document.reload.metadata.dig('faq_generation', 'faqs').size).to eq(result.size)
  end
end
