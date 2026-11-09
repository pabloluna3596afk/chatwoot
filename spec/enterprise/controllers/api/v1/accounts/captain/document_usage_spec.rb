require 'rails_helper'

RSpec.describe 'Captain document usage', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:base_url) { "/api/v1/accounts/#{account.id}/captain/documents" }
  let(:page_count) { 10 }
  let(:pdf_content) do
    objects = ['<< /Type /Catalog /Pages 2 0 R >>',
               "<< /Type /Pages /Count #{page_count} /Kids [#{(3...(page_count + 3)).map { |id| "#{id} 0 R" }.join(' ')}] >>"]
    page_count.times { objects << '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>' }
    data = "%PDF-1.4\n"
    offsets = [0]
    objects.each_with_index do |object, index|
      offsets << data.bytesize
      data << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end
    xref = data.bytesize
    data << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    data << offsets.drop(1).map { |offset| format("%010d 00000 n \n", offset) }.join
    data << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
  end
  let(:pdf) { Rack::Test::UploadedFile.new(StringIO.new(pdf_content), 'application/pdf', original_filename: 'knowledge.pdf') }

  describe 'POST estimate' do
    before do
      allow(OpenAI::Client).to receive(:new).and_raise('Estimate must not contact OpenAI')
      allow(RubyLLM).to receive(:chat).and_raise('Estimate must not contact an LLM')
    end

    [[1, 2], [10, 2], [11, 4], [200, 40], [201, 40]].each do |pages, units|
      context "with #{pages} pages" do
        let(:page_count) { pages }

        it 'counts real PDF pages, caps the estimate, and writes no ingestion or reservation rows' do
          expect do
            post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers
          end.not_to(change { [Captain::Document.count, ActiveStorage::Blob.count, AiUsageReservation.count, AiUsageEvent.count] })
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq('pages' => pages, 'units' => units, 'remaining' => nil, 'sufficient' => true)
        end
      end
    end

    it 'estimates the URL minimum without fetching its contents' do
      post "#{base_url}/estimate", params: { external_link: 'https://example.com/help' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('units' => Llm::UnitCosts.fetch(:text, :units_per_chunk), 'remaining' => nil, 'sufficient' => true)
    end

    it 'returns insufficient quota without reserving or consuming it' do
      put_account_on_plan(account, captain_internal_calls: 1)

      post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers

      expect(response.parsed_body).to include('remaining' => 1, 'sufficient' => false)
      expect(account.reload.current_usage_period.internal_calls_consumed).to eq(0)
      expect(AiUsageReservation.count).to eq(0)
    end

    it 'accepts the exact remaining quota' do
      put_account_on_plan(account, captain_internal_calls: 2)
      post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers

      expect(response.parsed_body).to include('remaining' => 2, 'sufficient' => true)
    end

    it 'accepts a plan with an unlimited internal quota' do
      put_account_on_plan(account, captain_internal_calls: nil)
      post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers

      expect(response.parsed_body).to include('remaining' => nil, 'sufficient' => true)
    end

    ['', '%PDF-1.4 corrupt'].each do |content|
      context "with invalid PDF #{content.inspect}" do
        let(:pdf_content) { content }

        it 'rejects the upload with a translated error' do
          post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq(I18n.t('captain.documents.invalid_pdf'))
        end
      end
    end

    context 'with an oversized PDF' do
      let(:pdf_content) { 'x' * (10.megabytes + 1) }

      it 'rejects before parsing' do
        post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('captain.documents.pdf_size_error'))
      end
    end

    [{}, { external_link: 'ftp://example.com' }, { external_link: [] }, { pdf_file: nil }, { pdf_file: 'not an upload' }].each do |input|
      it "rejects malformed input #{input.inspect}" do
        post "#{base_url}/estimate", params: input, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it 'rejects ambiguous sources' do
      post "#{base_url}/estimate", params: { pdf_file: pdf, external_link: 'https://example.com' }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'uses the same permission as uploading' do
      post "#{base_url}/estimate", params: { pdf_file: pdf }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires authentication' do
      post "#{base_url}/estimate", params: { external_link: 'https://example.com' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'does not persist or enqueue a PDF when the estimate exceeds quota' do
      put_account_on_plan(account, captain_internal_calls: 1)

      expect do
        post base_url, params: { document: { assistant_id: assistant.id, pdf_file: pdf } }, headers: headers
      end.not_to change(Captain::Document, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Captain::Documents::CrawlJob).not_to have_been_enqueued
    end

    it 'creates a document with exact quota without reserving it yet' do
      put_account_on_plan(account, captain_internal_calls: 2)

      expect do
        post base_url, params: { document: { assistant_id: assistant.id, pdf_file: pdf } }, headers: headers
      end.to change(Captain::Document, :count).by(1)
      expect(response).to have_http_status(:success)
      expect(AiUsageReservation.count).to eq(0)
    end
  end

  describe 'POST resume' do
    let(:document) { create(:captain_document, assistant: assistant, account: account, last_sync_error_code: 'usage_quota_exceeded') }
    let(:resume_url) { "#{base_url}/#{document.id}/resume" }

    it 'enqueues once and rejects a second click without losing the checkpoint' do
      put_account_on_plan(account, captain_internal_calls: 2)
      document.update!(metadata: document.metadata.merge('faq_generation' => { 'pages_processed' => 10, 'faqs' => [] }))

      expect { post resume_url, headers: headers }.to have_enqueued_job(Captain::Documents::ResponseBuilderJob).with(document)
      expect(response).to have_http_status(:accepted)
      expect(document.reload.last_sync_error_code).to be_nil
      expect(document.metadata.dig('faq_generation', 'pages_processed')).to eq(10)
      expect { post resume_url, headers: headers }.not_to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not enqueue when the next text chunk exceeds quota' do
      put_account_on_plan(account, captain_internal_calls: 2)
      document.update!(content: 'x' * (Llm::UnitCosts.fetch(:text, :characters_per_chunk) + 1))

      expect { post resume_url, headers: headers }.not_to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('captain.documents.usage_quota_exceeded'))
      expect(document.reload.last_sync_error_code).to eq('usage_quota_exceeded')
    end

    it 'supports accounts without a plan' do
      expect { post resume_url, headers: headers }.to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
      expect(response).to have_http_status(:accepted)
    end

    it 'only resumes quota-pending documents' do
      document.update!(last_sync_error_code: nil)

      expect { post resume_url, headers: headers }.not_to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'uses the same permission as sync' do
      expect { post resume_url, headers: agent.create_new_auth_token }.not_to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not expose documents from other accounts' do
      foreign_document = create(:captain_document)

      post "#{base_url}/#{foreign_document.id}/resume", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
