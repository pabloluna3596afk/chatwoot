require 'rails_helper'

RSpec.describe Whatsapp::Flows::PublishToMetaService do
  let(:account) { create(:account) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:waba_id) { channel.provider_config['business_account_id'] }
  let(:graph) { "https://graph.facebook.com/#{Whatsapp::Flows::MetaClient::GRAPH_VERSION}" }
  let(:auth) { { 'Authorization' => 'Bearer test_key' } }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  def stub_create(id: 'meta_flow_1')
    stub_request(:post, "#{graph}/#{waba_id}/flows").with(headers: auth)
                                                    .to_return(status: 200, body: { id: id }.to_json, headers: json_headers)
  end

  def stub_assets(errors: [], id: 'meta_flow_1')
    stub_request(:post, "#{graph}/#{id}/assets").with(headers: auth)
                                                .to_return(status: 200, body: { success: true,
                                                                                validation_errors: errors }.to_json, headers: json_headers)
  end

  def stub_publish(id: 'meta_flow_1')
    stub_request(:post, "#{graph}/#{id}/publish").with(headers: auth)
                                                 .to_return(status: 200, body: { success: true }.to_json, headers: json_headers)
  end

  def stub_status(status: 'PUBLISHED', id: 'meta_flow_1')
    stub_request(:get, %r{#{graph}/#{id}\?}).with(headers: auth)
                                            .to_return(status: 200, body: { id: id, status: status,
                                                                            validation_errors: [] }.to_json, headers: json_headers)
  end

  describe '#perform' do
    context 'when Meta accepts the flow' do
      before do
        stub_create
        stub_assets
        stub_publish
        stub_status
      end

      it 'creates the Meta flow, uploads the Flow JSON, publishes it and records the result' do
        result = described_class.new(flow, channel).perform

        expect(result).to include(success: true, status: 'published', meta_flow_id: 'meta_flow_1')
        publication = flow.whatsapp_flow_publications.sole
        expect(publication).to have_attributes(waba_id: waba_id, status: 'published', published_version: 1, account_id: account.id)
        expect(publication.published_at).to be_present
      end

      it 'creates the flow with the name and categories of the flow, with the channel token' do
        described_class.new(flow, channel).perform

        expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows")
          .with(body: { name: flow.name, categories: ['LEAD_GENERATION'] }.to_json, headers: auth).once
      end

      it 'uploads the exported Flow JSON as a FLOW_JSON asset' do
        described_class.new(flow, channel).perform

        expect(WebMock).to have_requested(:post, "#{graph}/meta_flow_1/assets")
          .with { |request| request.body.include?('FLOW_JSON') && request.body.include?('"screens"') }.once
      end

      it 'does not create a second Meta flow when it runs again' do
        described_class.new(flow, channel).perform
        described_class.new(flow, channel).perform

        expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows").once
        expect(WebMock).to have_requested(:post, "#{graph}/meta_flow_1/publish").once
        expect(flow.whatsapp_flow_publications.count).to eq(1)
      end
    end

    context 'when Meta finds errors in the Flow JSON' do
      let(:errors) { [{ 'error' => 'INVALID_PROPERTY', 'message' => 'bad value', 'pointers' => [{ 'path' => 'screens[0]' }] }] }

      before do
        stub_create
        stub_assets(errors: errors)
      end

      it 'keeps the errors, does not publish and stays a draft' do
        result = described_class.new(flow, channel).perform

        expect(result[:success]).to be false
        expect(result[:publication]).to have_attributes(status: 'draft', validation_errors: errors)
        expect(WebMock).not_to have_requested(:post, "#{graph}/meta_flow_1/publish")
      end

      it 'reuses the Meta flow on the retry' do
        described_class.new(flow, channel).perform
        stub_assets
        stub_publish
        stub_status
        result = described_class.new(flow, channel).perform

        expect(result).to include(success: true, status: 'published')
        expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows").once
      end
    end

    context 'when the definition is not valid' do
      before { flow.update_columns(definition: { 'schema_version' => 1, 'screens' => [{ 'title' => '', 'blocks' => [] }] }) } # rubocop:disable Rails/SkipsModelValidations

      it 'never calls Meta and stores the problems with their path' do
        result = described_class.new(flow, channel).perform

        expect(result[:success]).to be false
        expect(result[:publication].validation_errors.first).to include('path' => a_string_starting_with('screens.0'))
        expect(WebMock).not_to have_requested(:any, /graph.facebook.com/)
      end
    end

    context 'when Meta is down or refuses the call' do
      it 'stores Meta\'s message and marks the failure as retryable on a 5xx' do
        stub_request(:post, "#{graph}/#{waba_id}/flows")
          .to_return(status: 500, body: { error: { message: 'Service unavailable', code: 2 } }.to_json, headers: json_headers)

        result = described_class.new(flow, channel).perform

        expect(result).to include(success: false, retryable: true, error: 'Service unavailable')
        expect(result[:publication].validation_errors).to eq([{ 'error' => 'meta_error', 'message' => 'Service unavailable' }])
      end

      it 'does not retry a refused token and keeps the reason' do
        stub_request(:post, "#{graph}/#{waba_id}/flows")
          .to_return(status: 401, body: { error: { message: 'Invalid OAuth access token.', code: 190 } }.to_json, headers: json_headers)

        result = described_class.new(flow, channel).perform

        expect(result).to include(success: false, retryable: false, error: 'Invalid OAuth access token.')
      end

      it 'is retryable when the network fails' do
        stub_request(:post, "#{graph}/#{waba_id}/flows").to_timeout

        expect(described_class.new(flow, channel).perform).to include(success: false, retryable: true)
      end

      it 'never writes the token in the stored error' do
        stub_request(:post, "#{graph}/#{waba_id}/flows").to_timeout

        result = described_class.new(flow, channel).perform

        expect(result[:publication].validation_errors.to_json).not_to include('test_key')
      end
    end

    context 'when the flow is already published' do
      before do
        stub_create
        stub_assets
        stub_publish
        stub_status
        described_class.new(flow, channel).perform
        WebMock.reset_executed_requests!
      end

      it 'does nothing while the flow has not changed' do
        result = described_class.new(flow.reload, channel).perform

        expect(result).to include(success: true, status: 'published', meta_flow_id: 'meta_flow_1')
        expect(WebMock).not_to have_requested(:any, /graph.facebook.com/)
      end

      it 'goes through a new version when the flow changed' do
        flow.update!(name: 'Renombrado')
        version = instance_double(Whatsapp::Flows::VersionFlowService, perform: { success: true })
        allow(Whatsapp::Flows::VersionFlowService).to receive(:new).and_return(version)

        expect(described_class.new(flow.reload, channel).perform).to eq(success: true)
        expect(Whatsapp::Flows::VersionFlowService).to have_received(:new).with(flow, channel, flow.whatsapp_flow_publications.sole)
      end
    end
  end

  describe '#prepare_for_test' do
    it 'leaves a draft in Meta with the current Flow JSON and does not publish it' do
      stub_create
      stub_assets

      publication, meta_flow_id, mode = described_class.new(flow, channel).prepare_for_test

      expect(publication).to have_attributes(status: 'draft', meta_flow_id: 'meta_flow_1')
      expect([meta_flow_id, mode]).to eq(%w[meta_flow_1 draft])
      expect(WebMock).not_to have_requested(:post, "#{graph}/meta_flow_1/publish")
    end

    it 'answers the published flow while it has not changed' do
      stub_create
      stub_assets
      stub_publish
      stub_status
      described_class.new(flow, channel).perform

      _publication, meta_flow_id, mode = described_class.new(flow.reload, channel).prepare_for_test

      expect([meta_flow_id, mode]).to eq(%w[meta_flow_1 published])
    end

    it 'leaves Meta\'s errors in the publication when it refuses the Flow JSON' do
      stub_create
      stub_assets(errors: [{ 'error' => 'X', 'message' => 'bad' }])

      publication, meta_flow_id, = described_class.new(flow, channel).prepare_for_test

      expect(meta_flow_id).to eq('meta_flow_1')
      expect(publication.validation_errors?).to be true
    end
  end
end
