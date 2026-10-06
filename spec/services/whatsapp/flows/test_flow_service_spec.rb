require 'rails_helper'

RSpec.describe Whatsapp::Flows::TestFlowService do
  let(:account) { create(:account) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false).tap do |created|
      # the factory gives the phone number the same id as the WABA; keep them apart to prove which one is used
      created.update_columns(provider_config: created.provider_config.merge('phone_number_id' => '777000111')) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let(:waba_id) { channel.provider_config['business_account_id'] }
  let(:phone_number_id) { channel.provider_config['phone_number_id'] }
  let(:graph) { "https://graph.facebook.com/#{Whatsapp::Flows::MetaClient::GRAPH_VERSION}" }
  let(:auth) { { 'Authorization' => 'Bearer test_key' } }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:service) { described_class.new(flow, channel, '+593 99 123 4567') }

  def stub_draft_flow(errors: [])
    stub_request(:post, "#{graph}/#{waba_id}/flows").to_return(status: 200, body: { id: 'meta_flow_1' }.to_json, headers: json_headers)
    stub_request(:post, "#{graph}/meta_flow_1/assets")
      .to_return(status: 200, body: { success: true, validation_errors: errors }.to_json, headers: json_headers)
  end

  def stub_send(status: 200, body: { messages: [{ id: 'wamid.1' }] })
    stub_request(:post, "#{graph}/#{phone_number_id}/messages").with(headers: auth)
                                                               .to_return(status: status, body: body.to_json, headers: json_headers)
  end

  describe '#perform' do
    context 'with a flow that is still a draft' do
      before { stub_draft_flow }

      it 'sends it in draft mode through the phone number id, not the WABA' do
        stub_send

        expect(service.perform).to eq(success: true, message_id: 'wamid.1')
        expect(WebMock).to have_requested(:post, "#{graph}/#{phone_number_id}/messages").with(headers: auth) { |request|
          body = JSON.parse(request.body)
          parameters = body['interactive']['action']['parameters']
          body['to'] == '593991234567' && body['type'] == 'interactive' && body['interactive']['type'] == 'flow' &&
            parameters['mode'] == 'draft' && parameters['flow_id'] == 'meta_flow_1' &&
            parameters['flow_action_payload']['screen'] == flow.flow_json['screens'].first['id']
        }.once
        expect(WebMock).not_to have_requested(:post, "#{graph}/#{waba_id}/messages")
      end

      it 'does not publish the flow' do
        stub_send
        service.perform

        expect(WebMock).not_to have_requested(:post, "#{graph}/meta_flow_1/publish")
      end

      it 'returns Meta\'s reason when it refuses the message (24 h window)' do
        stub_send(status: 400, body: { error: { message: 'Re-engagement message', code: 131_047 } })

        expect(service.perform).to eq(success: false, error: 'Re-engagement message')
      end
    end

    context 'with a flow Meta finds errors in' do
      it 'does not send and shows the errors' do
        stub_draft_flow(errors: [{ 'error' => 'INVALID_PROPERTY', 'message' => 'bad value' }])

        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to include('bad value')
        expect(WebMock).not_to have_requested(:post, "#{graph}/#{phone_number_id}/messages")
      end
    end

    context 'with a flow already published' do
      before do
        WhatsappFlowPublication.create!(whatsapp_flow_id: flow.id, account_id: account.id, waba_id: waba_id, status: 'published',
                                        meta_flow_id: 'live_flow', published_version: 1, published_at: 1.minute.from_now)
      end

      it 'sends the published flow as it is' do
        stub_send

        expect(service.perform).to include(success: true)
        expect(WebMock).to(have_requested(:post, "#{graph}/#{phone_number_id}/messages").with do |request|
          parameters = JSON.parse(request.body)['interactive']['action']['parameters']
          parameters['mode'] == 'published' && parameters['flow_id'] == 'live_flow'
        end)
      end

      context 'when the flow changed after it was published' do
        before do
          WhatsappFlowPublication.update_all(published_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
          flow.update!(name: 'Cambiado')
          stub_request(:post, "#{graph}/#{waba_id}/flows").to_return(status: 200, body: { id: 'draft_clone' }.to_json, headers: json_headers)
          stub_request(:post, "#{graph}/draft_clone/assets")
            .to_return(status: 200, body: { success: true, validation_errors: [] }.to_json, headers: json_headers)
          stub_send
        end

        it 'sends a draft clone in draft mode, without publishing and without touching the published flow' do
          expect(described_class.new(flow.reload, channel, '593991234567').perform).to include(success: true)

          expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows")
            .with(body: { name: 'Cambiado', categories: ['LEAD_GENERATION'], clone_flow_id: 'live_flow' }.to_json).once
          expect(WebMock).to(have_requested(:post, "#{graph}/#{phone_number_id}/messages").with do |request|
            parameters = JSON.parse(request.body)['interactive']['action']['parameters']
            parameters['mode'] == 'draft' && parameters['flow_id'] == 'draft_clone'
          end)
          expect(WebMock).not_to have_requested(:post, %r{#{graph}/(live_flow|draft_clone)/publish})
          expect(WhatsappFlowPublication.sole).to have_attributes(meta_flow_id: 'live_flow', draft_meta_flow_id: 'draft_clone', status: 'published')
        end

        it 'reuses the draft clone on the next test' do
          2.times { described_class.new(flow.reload, channel, '593991234567').perform }

          expect(WebMock).to have_requested(:post, "#{graph}/#{waba_id}/flows").once
          expect(WebMock).to have_requested(:post, "#{graph}/draft_clone/assets").twice
        end
      end
    end

    it 'needs a phone number' do
      expect(described_class.new(flow, channel, ' ').perform).to eq(success: false, error: 'Phone number required')
    end

    it 'reports a channel without a phone number id instead of calling the WABA' do
      stub_draft_flow
      channel.update_columns(provider_config: channel.provider_config.except('phone_number_id')) # rubocop:disable Rails/SkipsModelValidations

      expect(service.perform).to eq(success: false, error: 'The channel has no phone number id')
    end
  end
end
