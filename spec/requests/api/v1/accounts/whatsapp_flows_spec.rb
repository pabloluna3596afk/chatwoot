require 'rails_helper'

# The Meta side of the flows API (publish, status, test, retry). The rest of the endpoints (index, show, create, update,
# destroy, validate) are covered in spec/controllers/api/v1/accounts/whatsapp_flows_controller_spec.rb.
RSpec.describe 'WhatsApp flows to Meta API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let!(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/whatsapp_flows/#{flow.id}" }

  describe 'POST publish' do
    it 'queues the publication for every Cloud WABA and answers the state to poll' do
      expect { post "#{base_path}/publish", headers: admin.create_new_auth_token, as: :json }
        .to have_enqueued_job(Whatsapp::PublishFlowToMetaJob).with(flow.id, account.id)

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body).to include('flow_id' => flow.id, 'publications' => [])
      expect(body['wabas']).to eq([{ 'waba_id' => channel.provider_config['business_account_id'], 'channel_id' => channel.id,
                                     'phone_number' => channel.phone_number, 'inbox_name' => channel.inbox&.name }])
    end

    it 'refuses when the account has no Cloud channel' do
      channel.update_columns(provider: 'default') # rubocop:disable Rails/SkipsModelValidations

      expect { post "#{base_path}/publish", headers: admin.create_new_auth_token, as: :json }
        .not_to have_enqueued_job(Whatsapp::PublishFlowToMetaJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_cloud_channels')
    end

    it 'is admin only' do
      expect { post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json }
        .not_to have_enqueued_job(Whatsapp::PublishFlowToMetaJob)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET publication_status' do
    it 'adds paginated WABA detail on demand without changing the legacy response' do
      get "#{base_path}/publication_status", params: { page: '1', per_page: '5' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['rows'].pluck('waba_id')).to eq([channel.provider_config['business_account_id']])
      expect(body['rows'].first['numbers']).to include(a_hash_including('channel_id' => channel.id, 'phone_number' => channel.phone_number))
      expect(body['meta']).to eq('current_page' => 1, 'per_page' => 5, 'total_count' => 1)
      expect(body.to_json).not_to include('provider_config', 'api_key', 'test_key')

      get "#{base_path}/publication_status", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('wabas', 'publications')
      expect(response.parsed_body).not_to have_key('rows')
    end

    it 'restricts paginated WABA details to admins and validates filters' do
      get "#{base_path}/publication_status", params: { page: '1' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      get "#{base_path}/publication_status", params: { page: '1', state: 'partial' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lists what Meta said for each WABA, with the errors' do
      WhatsappFlowPublication.create!(whatsapp_flow_id: flow.id, account_id: account.id, waba_id: '123456789', status: 'draft',
                                      meta_flow_id: 'meta_1', validation_errors: [{ 'error' => 'X', 'message' => 'bad' }])

      get "#{base_path}/publication_status", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['publications']).to contain_exactly(
        a_hash_including('waba_id' => '123456789', 'status' => 'draft', 'meta_flow_id' => 'meta_1',
                         'validation_errors' => [{ 'error' => 'X', 'message' => 'bad' }])
      )
    end

    it 'is admin only' do
      get "#{base_path}/publication_status", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not show a flow of another account' do
      other = create(:whatsapp_flow)

      get "/api/v1/accounts/#{account.id}/whatsapp_flows/#{other.id}/publication_status", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST test' do
    let(:service) { instance_double(Whatsapp::Flows::TestFlowService) }

    before { allow(Whatsapp::Flows::TestFlowService).to receive(:new).and_return(service) }

    it 'sends the flow to the number through the chosen Cloud channel' do
      allow(service).to receive(:perform).and_return(success: true, message_id: 'wamid.1')

      post "#{base_path}/test", params: { channel_id: channel.id, phone_number: '+593991234567' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('success' => true, 'message_id' => 'wamid.1')
      expect(Whatsapp::Flows::TestFlowService).to have_received(:new).with(flow, channel, '+593991234567')
    end

    it 'answers Meta\'s reason when it cannot send' do
      allow(service).to receive(:perform).and_return(success: false, error: 'Re-engagement message')

      post "#{base_path}/test", params: { channel_id: channel.id, phone_number: '593991234567' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('success' => false, 'error' => 'Re-engagement message')
    end

    it 'only accepts a Cloud channel of the account' do
      other = create(:channel_whatsapp, provider: 'default', account: account, validate_provider_config: false, sync_templates: false)

      post "#{base_path}/test", params: { channel_id: other.id, phone_number: '593991234567' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'is admin only' do
      post "#{base_path}/test", params: { channel_id: channel.id, phone_number: '593991234567' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST publications/:waba_id/retry' do
    before { WhatsappFlowPublication.create!(whatsapp_flow_id: flow.id, account_id: account.id, waba_id: '123456789', status: 'draft') }

    it 'queues the publication of just that WABA' do
      expect { post "#{base_path}/publications/123456789/retry", headers: admin.create_new_auth_token, as: :json }
        .to have_enqueued_job(Whatsapp::PublishFlowToMetaJob).with(flow.id, account.id, '123456789')

      expect(response).to have_http_status(:accepted)
    end

    it 'answers 404 for a WABA the flow was never sent to' do
      post "#{base_path}/publications/555/retry", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'is admin only' do
      post "#{base_path}/publications/123456789/retry", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
