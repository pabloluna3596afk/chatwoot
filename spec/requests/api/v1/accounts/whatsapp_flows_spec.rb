require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::WhatsappFlowsController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:whatsapp_flow) { create(:whatsapp_flow, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider_config: {
      'business_account_id' => '1554207416398687',
      'access_token' => 'test_token'
    })
  end

  let(:base_path) { "/api/v1/accounts/#{account.id}/whatsapp_flows" }

  before do
    channel
    allow_any_instance_of(Whatsapp::PublishFlowToMetaJob).to receive(:perform).and_return(true)
  end

  describe 'POST #publish' do
    it 'admin can publish' do
      sign_in admin_user

      post "#{base_path}/#{whatsapp_flow.id}/publish", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include('flow_id')
    end

    it 'agent gets 403' do
      sign_in agent_user

      post "#{base_path}/#{whatsapp_flow.id}/publish", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET #publication_status' do
    it 'returns publication status for all WABAs' do
      sign_in admin_user
      create(:whatsapp_flow_publication, whatsapp_flow: whatsapp_flow, account: account, waba_id: '1554207416398687', status: 'published')

      get "#{base_path}/#{whatsapp_flow.id}/publication_status", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['publications']).to be_an(Array)
    end
  end

  describe 'POST #test' do
    it 'admin can send test message' do
      sign_in admin_user
      create(:whatsapp_flow_publication, whatsapp_flow: whatsapp_flow, account: account, waba_id: '1554207416398687', meta_flow_id: '555000')

      allow_any_instance_of(Whatsapp::Flows::TestFlowService).to receive(:perform).and_return({ success: true, message_id: '123' })

      post "#{base_path}/#{whatsapp_flow.id}/test",
           params: { phone_number: '+551140414141', channel_id: channel.id },
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('success' => true)
    end

    it 'agent gets 403' do
      sign_in agent_user

      post "#{base_path}/#{whatsapp_flow.id}/test",
           params: { phone_number: '+551140414141', channel_id: channel.id },
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST #retry_publish' do
    it 'admin can retry failed publication' do
      sign_in admin_user
      create(:whatsapp_flow_publication, whatsapp_flow: whatsapp_flow, account: account, waba_id: '1554207416398687', status: 'draft')

      allow_any_instance_of(Whatsapp::Flows::PublishToMetaService).to receive(:perform).and_return({ success: true })

      post "#{base_path}/#{whatsapp_flow.id}/publications/1554207416398687/retry",
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 if publication not found' do
      sign_in admin_user

      post "#{base_path}/#{whatsapp_flow.id}/publications/invalid_waba/retry",
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:not_found)
    end
  end
end
