require 'rails_helper'

RSpec.describe Whatsapp::TemplateHeaderHandleService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:service) { described_class.new(channel) }
  let(:token) { channel.template_access_token }
  let(:base) { "https://graph.facebook.com/#{described_class::API_VERSION}" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:file) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def stub_app(app_id: '4242')
    stub_request(:get, "#{base}/debug_token").with(query: { input_token: token }, headers: { 'Authorization' => "Bearer #{token}" })
                                             .to_return(status: 200, headers: json, body: { data: { app_id: app_id } }.to_json)
  end

  describe '#available?' do
    it 'finds the app of the channel token and remembers it' do
      stub = stub_app

      expect(service.available?).to be true
      expect(described_class.new(channel).available?).to be true
      expect(stub).to have_been_requested.once
    end

    it 'is false when the token cannot introspect itself' do
      stub_request(:get, "#{base}/debug_token").with(query: { input_token: token })
                                               .to_return(status: 400, headers: json, body: { error: { code: 100 } }.to_json)

      expect(service.available?).to be false
    end

    it 'is false when Meta cannot be reached' do
      stub_request(:get, "#{base}/debug_token").with(query: { input_token: token }).to_timeout

      expect(service.available?).to be false
    end
  end

  describe '#upload!' do
    it 'opens an upload session on the app and uploads the bytes' do
      stub_app
      session = stub_request(:post, "#{base}/4242/uploads")
                .with(query: hash_including(file_type: 'image/png', file_name: 'avatar.png'), headers: { 'Authorization' => "Bearer #{token}" })
                .to_return(status: 200, headers: json, body: { id: 'upload:abc' }.to_json)
      bytes = stub_request(:post, "#{base}/upload:abc")
              .with(headers: { 'Authorization' => "OAuth #{token}", 'File-Offset' => '0' })
              .to_return(status: 200, headers: json, body: { h: '4::handle' }.to_json)

      expect(service.upload!(file)).to eq('4::handle')
      expect(session).to have_been_requested
      expect(bytes).to have_been_requested
    end

    it 'raises media_header_unavailable without an app' do
      stub_request(:get, "#{base}/debug_token").with(query: { input_token: token }).to_return(status: 400, headers: json, body: '{}')

      expect { service.upload!(file) }.to raise_error(described_class::Error, 'media_header_unavailable')
    end

    it 'raises upload_failed when Meta refuses the session or the bytes, without logging the token' do
      stub_app
      stub_request(:post, "#{base}/4242/uploads").with(query: hash_including({})).to_return(status: 400, headers: json, body: '{}')
      allow(Rails.logger).to receive(:warn)

      expect { service.upload!(file) }.to raise_error(described_class::Error, 'upload_failed')
      expect(Rails.logger).to have_received(:warn).with(satisfy { |line| line.exclude?(token.to_s) }).at_least(:once)
    end
  end
end
