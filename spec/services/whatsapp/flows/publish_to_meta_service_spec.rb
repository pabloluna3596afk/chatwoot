require 'rails_helper'

RSpec.describe Whatsapp::Flows::PublishToMetaService, type: :service do
  let(:account) { create(:account) }
  let(:whatsapp_flow) { create(:whatsapp_flow, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider_config: {
      'business_account_id' => '1554207416398687',
      'access_token' => 'test_token_123'
    })
  end

  let(:service) { described_class.new(whatsapp_flow, channel) }

  describe '#perform' do
    context 'successful publish' do
      before do
        stub_meta_create_flow_request
        stub_meta_upload_asset_request
        stub_meta_publish_request
        stub_meta_get_flow_request
      end

      it 'creates publication record' do
        result = service.perform

        expect(result[:success]).to be true
        expect(result[:publication]).to be_persisted
        expect(result[:publication].status).to eq('published')
        expect(result[:publication].meta_flow_id).to eq('555000123456789')
      end

      it 'idempotent: reuse meta_flow_id on double call' do
        result1 = service.perform
        meta_flow_id1 = result1[:publication].meta_flow_id

        result2 = described_class.new(whatsapp_flow, channel).perform
        meta_flow_id2 = result2[:publication].meta_flow_id

        expect(meta_flow_id1).to eq(meta_flow_id2)
        expect(WhatsappFlowPublication.where(
          whatsapp_flow_id: whatsapp_flow.id,
          waba_id: '1554207416398687'
        ).count).to eq(1)
      end

      it 'set published_at timestamp' do
        result = service.perform

        expect(result[:publication].published_at).to be_present
      end
    end

    context 'validation errors from Meta' do
      before do
        stub_meta_create_flow_request
        stub_meta_upload_asset_request_with_errors
        stub_meta_publish_request
        stub_meta_get_flow_request
      end

      it 'stores validation_errors array' do
        result = service.perform

        expect(result[:publication].validation_errors).to be_an(Array)
        expect(result[:publication].has_validation_errors?).to be true
        expect(result[:publication].validation_errors.first).to include('error_code')
      end
    end

    context 'Meta API errors' do
      it 'returns error on create failure' do
        stub_request(:post, %r{graph.facebook.com/v22.0/1554207416398687/flows})
          .to_return(status: 400, body: { error: { message: 'Invalid category' } }.to_json)

        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it 'handles 5xx errors gracefully' do
        stub_request(:post, %r{graph.facebook.com/v22.0/1554207416398687/flows})
          .to_return(status: 500, body: { error: 'Server error' }.to_json)

        result = service.perform

        expect(result[:success]).to be false
      end
    end

    context 'missing config' do
      it 'raises when WABA ID missing' do
        channel.provider_config.delete('business_account_id')

        expect { service.perform }.to raise_error('WABA ID not found in channel config')
      end

      it 'raises when access token missing' do
        channel.provider_config.delete('access_token')

        expect { service.perform }.to raise_error('Access token not found in channel config')
      end
    end
  end

  private

  def stub_meta_create_flow_request(status: 200, error: nil)
    if error
      stub_request(:post, %r{graph.facebook.com/v22.0/1554207416398687/flows})
        .to_return(status: status, body: { error: error }.to_json)
    else
      stub_request(:post, %r{graph.facebook.com/v22.0/1554207416398687/flows})
        .to_return(status: status, body: { id: '555000123456789' }.to_json)
    end
  end

  def stub_meta_upload_asset_request
    stub_request(:post, %r{graph.facebook.com/v22.0/555000123456789/assets})
      .to_return(status: 200, body: { success: true, validation_errors: [] }.to_json)
  end

  def stub_meta_upload_asset_request_with_errors
    stub_request(:post, %r{graph.facebook.com/v22.0/555000123456789/assets})
      .to_return(status: 200, body: {
        success: false,
        validation_errors: [
          { error_code: 131000, error_description: 'Invalid flow JSON', possible_solution: 'Fix syntax' }
        ]
      }.to_json)
  end

  def stub_meta_publish_request
    stub_request(:post, %r{graph.facebook.com/v22.0/555000123456789/publish})
      .to_return(status: 200, body: { success: true }.to_json)
  end

  def stub_meta_get_flow_request
    stub_request(:get, %r{graph.facebook.com/v22.0/555000123456789})
      .to_return(status: 200, body: { id: '555000123456789', status: 'PUBLISHED', validation_errors: [] }.to_json)
  end
end
