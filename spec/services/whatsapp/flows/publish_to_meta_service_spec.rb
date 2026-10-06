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

  before do
    stub_meta_create_flow_request
    stub_meta_upload_asset_request
    stub_meta_publish_request
    stub_meta_get_flow_request
  end

  describe '#perform' do
    context 'when flow publishes successfully' do
      it 'creates a publication record' do
        result = service.perform

        expect(result[:success]).to be true
        expect(result[:publication]).to be_persisted
        expect(result[:publication].status).to eq('published')
      end

      it 'stores meta_flow_id' do
        result = service.perform

        expect(result[:publication].meta_flow_id).to eq('555000123456789')
      end

      it 'creates unique constraint per waba' do
        service.perform

        expect do
          described_class.new(whatsapp_flow, channel).perform
        end.not_to raise_error

        expect(WhatsappFlowPublication.where(
          whatsapp_flow_id: whatsapp_flow.id,
          waba_id: channel.provider_config['business_account_id']
        ).count).to eq(1)
      end
    end

    context 'when validation errors exist in Meta' do
      it 'stores validation errors' do
        stub_meta_upload_asset_request_with_errors

        result = service.perform

        expect(result[:publication].validation_errors).to be_present
        expect(result[:publication].has_validation_errors?).to be true
      end
    end

    context 'when Meta API fails' do
      it 'returns error' do
        stub_meta_create_flow_request(status: 400, error: 'Invalid request')

        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'when channel config is missing' do
      it 'raises error for missing WABA ID' do
        channel.provider_config.delete('business_account_id')

        expect { service.perform }.to raise_error('WABA ID not found in channel config')
      end

      it 'raises error for missing access token' do
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
          { error_code: 131000, error_description: 'Invalid flow JSON', possible_solution: 'Fix the JSON syntax' }
        ]
      }.to_json)
  end

  def stub_meta_publish_request
    stub_request(:post, %r{graph.facebook.com/v22.0/555000123456789/publish})
      .to_return(status: 200, body: { success: true }.to_json)
  end

  def stub_meta_get_flow_request
    stub_request(:get, %r{graph.facebook.com/v22.0/555000123456789})
      .to_return(status: 200, body: {
        id: '555000123456789',
        status: 'PUBLISHED',
        validation_errors: []
      }.to_json)
  end
end
