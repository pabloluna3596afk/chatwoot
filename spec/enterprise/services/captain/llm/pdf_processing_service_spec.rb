require 'rails_helper'

RSpec.describe Captain::Llm::PdfProcessingService do
  let(:document) { create(:captain_document) }
  let(:service) { described_class.new(document) }

  before do
    # Mock OpenAI configuration
    installation_config = instance_double(InstallationConfig, value: 'test-api-key')
    allow(InstallationConfig).to receive(:find_by!)
      .with(name: 'CAPTAIN_OPEN_AI_API_KEY')
      .and_return(installation_config)
  end

  describe '#process' do
    context 'when document already has OpenAI file ID' do
      before do
        allow(document).to receive(:openai_file_id).and_return('existing-file-id')
      end

      it 'skips upload' do
        expect(document).not_to receive(:store_openai_file_id)
        service.process
      end
    end

    context 'when uploading PDF to OpenAI' do
      let(:mock_client) { instance_double(OpenAI::Client) }
      let(:pdf_content) { 'PDF content' }
      let(:blob_double) { instance_double(ActiveStorage::Blob) }
      let(:pdf_file) { instance_double(ActiveStorage::Attachment) }

      before do
        allow(document).to receive(:openai_file_id).and_return(nil)
        allow(document).to receive(:pdf_file).and_return(pdf_file)
        allow(pdf_file).to receive(:blob).and_return(blob_double)
        allow(blob_double).to receive(:open).and_yield(StringIO.new(pdf_content))

        allow(OpenAI::Client).to receive(:new).and_return(mock_client)
        # Use a simple double for OpenAI::Files as it may not be loaded
        files_api = double('files_api') # rubocop:disable RSpec/VerifiedDoubles
        allow(files_api).to receive(:upload).and_return({ 'id' => 'file-abc123' })
        allow(mock_client).to receive(:files).and_return(files_api)
      end

      it 'uploads PDF and stores file ID' do
        expect(document).to receive(:store_openai_file_id).with('file-abc123')
        service.process
      end

      it 'raises error when upload fails' do
        allow(mock_client.files).to receive(:upload).and_return({ 'id' => nil })

        expect { service.process }.to raise_error(CustomExceptions::Pdf::UploadError)
      end

      it 'uploads the PDF again after its OpenAI file is deleted' do
        file_id = 'file-previous'
        allow(document).to receive(:openai_file_id) { file_id }
        allow(document).to receive(:update!) { |attributes| file_id = attributes[:openai_file_id] }
        allow(mock_client.files).to receive(:delete).with(id: 'file-previous')
        allow(mock_client.files).to receive(:upload).and_return({ 'id' => 'file-new' })

        service.delete_openai_file

        expect(document).to receive(:store_openai_file_id).with('file-new')
        service.process
      end
    end
  end

  describe '#delete_openai_file' do
    let(:mock_client) { instance_double(OpenAI::Client) }
    let(:files_api) { double('files_api') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:files).and_return(files_api)
      allow(document).to receive(:openai_file_id).and_return('file-123')
      allow(document).to receive(:destroyed?).and_return(false)
    end

    it 'deletes the file and clears its ID' do
      expect(files_api).to receive(:delete).with(id: 'file-123')
      expect(document).to receive(:update!).with(openai_file_id: nil)

      service.delete_openai_file
    end

    it 'does not raise or clear the ID when the provider fails' do
      allow(files_api).to receive(:delete).and_raise(StandardError, 'provider unavailable')

      expect(document).not_to receive(:update!)
      expect { service.delete_openai_file }.not_to raise_error
    end

    it 'treats a 404 as already deleted and clears the ID' do
      error = Faraday::ResourceNotFound.new('not found', { status: 404 })
      allow(files_api).to receive(:delete).and_raise(error)

      expect(document).to receive(:update!).with(openai_file_id: nil)
      service.delete_openai_file
    end
  end
end
