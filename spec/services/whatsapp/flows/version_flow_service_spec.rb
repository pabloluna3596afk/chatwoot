require 'rails_helper'

RSpec.describe Whatsapp::Flows::VersionFlowService do
  let(:account) { create(:account) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:waba_id) { channel.provider_config['business_account_id'] }
  let(:graph) { "https://graph.facebook.com/#{Whatsapp::Flows::MetaClient::GRAPH_VERSION}" }
  let(:auth) { { 'Authorization' => 'Bearer test_key' } }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let!(:publication) do
    create_publication(status: 'published', meta_flow_id: 'old_flow', published_version: 1, published_at: 1.hour.ago)
  end

  def create_publication(**attributes)
    WhatsappFlowPublication.create!({ whatsapp_flow_id: flow.id, account_id: account.id, waba_id: waba_id }.merge(attributes))
  end

  def stub_ok(verb, path, body = { success: true })
    stub_request(verb, "#{graph}/#{path}").with(headers: auth).to_return(status: 200, body: body.to_json, headers: json_headers)
  end

  describe '#perform' do
    context 'when the new version goes through' do
      before do
        stub_request(:post, "#{graph}/#{waba_id}/flows").with(headers: auth)
                                                        .to_return(status: 200, body: { id: 'new_flow' }.to_json, headers: json_headers)
        stub_ok(:post, 'new_flow/assets', success: true, validation_errors: [])
        stub_ok(:post, 'new_flow/publish')
        stub_request(:get, %r{#{graph}/new_flow\?}).to_return(status: 200, body: { id: 'new_flow', status: 'PUBLISHED' }.to_json,
                                                              headers: json_headers)
        stub_ok(:post, 'old_flow/deprecate')
      end

      it 'clones the published flow, publishes the clone and deprecates the old one' do
        result = described_class.new(flow, channel, publication).perform

        expect(result).to include(success: true, meta_flow_id: 'new_flow', old_meta_flow_id: 'old_flow')
        expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows")
          .with(body: { name: flow.name, categories: ['LEAD_GENERATION'], clone_flow_id: 'old_flow' }.to_json)
        expect(WebMock).to have_requested(:post, "#{graph}/old_flow/deprecate").once
      end

      it 'points the same publication at the new flow and counts the version' do
        described_class.new(flow, channel, publication).perform

        expect(publication.reload).to have_attributes(meta_flow_id: 'new_flow', old_meta_flow_id: 'old_flow', status: 'published',
                                                      published_version: 2, validation_errors: [])
        expect(flow.whatsapp_flow_publications.count).to eq(1)
      end
    end

    context 'when "Probar" already left a draft clone' do
      before do
        publication.update!(draft_meta_flow_id: 'draft_clone')
        stub_ok(:post, 'draft_clone/assets', success: true, validation_errors: [])
        stub_ok(:post, 'draft_clone/publish')
        stub_request(:get, %r{#{graph}/draft_clone\?}).to_return(status: 200, body: { id: 'draft_clone', status: 'PUBLISHED' }.to_json,
                                                                 headers: json_headers)
        stub_ok(:post, 'old_flow/deprecate')
      end

      it 'publishes that draft instead of cloning again, and deprecates the old flow' do
        result = described_class.new(flow, channel, publication).perform

        expect(result).to include(success: true, meta_flow_id: 'draft_clone', old_meta_flow_id: 'old_flow')
        expect(WebMock).not_to have_requested(:post, "#{graph}/#{waba_id}/flows")
        expect(publication.reload).to have_attributes(meta_flow_id: 'draft_clone', draft_meta_flow_id: nil, published_version: 2)
      end

      it 'keeps the draft clone when Meta finds errors in it' do
        stub_ok(:post, 'draft_clone/assets', success: true, validation_errors: [{ 'error' => 'X', 'message' => 'bad' }])

        expect(described_class.new(flow, channel, publication).perform).to include(success: false)
        expect(publication.reload.draft_meta_flow_id).to eq('draft_clone')
        expect(WebMock).not_to have_requested(:delete, "#{graph}/draft_clone")
      end
    end

    context 'when Meta finds errors in the new Flow JSON' do
      let(:errors) { [{ 'error' => 'INVALID_PROPERTY', 'message' => 'bad value' }] }

      before do
        stub_request(:post, "#{graph}/#{waba_id}/flows").to_return(status: 200, body: { id: 'new_flow' }.to_json, headers: json_headers)
        stub_ok(:post, 'new_flow/assets', success: true, validation_errors: errors)
        stub_ok(:delete, 'new_flow')
      end

      it 'deletes the unfinished flow, keeps the old one published and shows the errors' do
        result = described_class.new(flow, channel, publication).perform

        expect(result).to include(success: false, retryable: false)
        expect(publication.reload).to have_attributes(meta_flow_id: 'old_flow', status: 'published', validation_errors: errors)
        expect(WebMock).to have_requested(:delete, "#{graph}/new_flow").once
        expect(WebMock).not_to have_requested(:post, "#{graph}/old_flow/deprecate")
      end
    end

    context 'when Meta refuses a step' do
      it 'keeps the old flow, stores Meta\'s message and flags 5xx as retryable' do
        stub_request(:post, "#{graph}/#{waba_id}/flows")
          .to_return(status: 503, body: { error: { message: 'Try later' } }.to_json, headers: json_headers)

        result = described_class.new(flow, channel, publication).perform

        expect(result).to include(success: false, retryable: true, error: 'Try later')
        expect(publication.reload).to have_attributes(meta_flow_id: 'old_flow', status: 'published')
        expect(publication.validation_errors).to eq([{ 'error' => 'meta_error', 'message' => 'Try later' }])
      end

      it 'does not fail the new version when only the deprecation of the old one fails' do
        stub_request(:post, "#{graph}/#{waba_id}/flows").to_return(status: 200, body: { id: 'new_flow' }.to_json, headers: json_headers)
        stub_ok(:post, 'new_flow/assets', success: true, validation_errors: [])
        stub_ok(:post, 'new_flow/publish')
        stub_request(:get, %r{#{graph}/new_flow\?}).to_return(status: 200, body: { id: 'new_flow', status: 'PUBLISHED' }.to_json,
                                                              headers: json_headers)
        stub_request(:post, "#{graph}/old_flow/deprecate").to_return(status: 400, body: { error: { message: 'nope' } }.to_json, headers: json_headers)

        expect(described_class.new(flow, channel, publication).perform).to include(success: true, meta_flow_id: 'new_flow')
      end
    end

    it 'refuses a publication that is not published' do
      publication.update!(status: 'draft')

      expect(described_class.new(flow, channel, publication).perform).to include(success: false)
      expect(WebMock).not_to have_requested(:any, /graph.facebook.com/)
    end
  end
end
