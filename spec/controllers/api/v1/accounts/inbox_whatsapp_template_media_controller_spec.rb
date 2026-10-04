require 'rails_helper'

RSpec.describe 'Inbox WhatsApp template header media API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_template_media" }
  let(:png) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  describe 'POST /api/v1/accounts/{account.id}/inboxes/{inbox.id}/whatsapp_template_media' do
    it 'requires authentication' do
      post url, params: { header_format: 'IMAGE', file: png }

      expect(response).to have_http_status(:unauthorized)
    end

    context 'with an agent of the inbox' do
      before { create(:inbox_member, inbox: inbox, user: agent) }

      it 'uploads the file once to Meta and returns the header params to keep' do
        allow(Whatsapp::MediaUploadService).to receive(:upload_blob!).and_return('media_555')

        post url, params: { header_format: 'IMAGE', file: png }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body).to include('media_id' => 'media_555', 'media_type' => 'image', 'media_name' => 'avatar.png')
        expect(body['media_phone_number_id']).to eq(channel.provider_config['phone_number_id'])
        expect(ActiveStorage::Blob.find_signed(body['media_blob']).metadata['account_id']).to eq(account.id)
        expect(Whatsapp::MediaUploadService).to have_received(:upload_blob!).once
      end

      it 'refuses a file the header does not accept' do
        allow(Whatsapp::MediaUploadService).to receive(:upload_blob!)

        post url, params: { header_format: 'DOCUMENT', file: png }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_type')
        expect(Whatsapp::MediaUploadService).not_to have_received(:upload_blob!)
      end

      it 'asks for the file' do
        post url, params: { header_format: 'IMAGE' }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('file_required')
      end

      it 'reports a refused upload as a bad gateway' do
        allow(Whatsapp::MediaUploadService).to receive(:upload_blob!)
          .and_raise(Whatsapp::MediaUploadService::UploadError, 'HTTP 400 bad media')

        post url, params: { header_format: 'IMAGE', file: png }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body).to include('error' => 'upload_failed')
      end
    end

    context 'with an agent that is not in the inbox' do
      it 'is unauthorized' do
        post url, params: { header_format: 'IMAGE', file: png }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the inbox is not WhatsApp Cloud' do
      let(:channel) { create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false) }

      before { create(:inbox_member, inbox: inbox, user: agent) }

      it 'is a bad request' do
        post url, params: { header_format: 'IMAGE', file: png }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
