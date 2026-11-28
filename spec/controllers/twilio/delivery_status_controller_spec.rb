require 'rails_helper'

RSpec.describe 'Twilio::DeliveryStatusController', type: :request do
  include Rails.application.routes.url_helpers

  describe 'POST /twilio/delivery_status' do
    let(:params) do
      {
        'MessageSid' => 'SM123',
        'MessageStatus' => 'delivered',
        'AccountSid' => 'AC123'
      }
    end

    it 'enqueues the Twilio delivery status job' do
      expect do
        post twilio_delivery_status_index_url, params: params
      end.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob).with(params)
    end

    it 'returns no content status' do
      post twilio_delivery_status_index_url, params: params
      expect(response).to have_http_status(:no_content)
    end

    context 'when the request resolves to a channel' do
      let(:channel) { create(:channel_twilio_sms, :with_phone_number) }
      let(:params) do
        { 'MessageSid' => 'SM456', 'MessageStatus' => 'delivered', 'AccountSid' => channel.account_sid, 'From' => channel.phone_number }
      end
      let(:signature) { Twilio::Security::RequestValidator.new(channel.auth_token).build_signature_for(twilio_delivery_status_index_url, params) }

      it 'logs unsigned requests and still enqueues them' do
        expect(Rails.logger).to receive(:warn).with(
          "[TWILIO] Invalid webhook signature channel_id=#{channel.id} endpoint=delivery_status enforced=false"
        )

        expect do
          post twilio_delivery_status_index_url, params: params
        end.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('delivery_status_signature_enforced')
      end

      it 'accepts valid signatures without enabling enforcement' do
        expect(Rails.logger).not_to receive(:warn).with(/Invalid webhook signature/)

        expect do
          post twilio_delivery_status_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }
        end.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('delivery_status_signature_enforced')
      end

      it 'continues logging invalid signatures after receiving a valid signature' do
        post twilio_delivery_status_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }
        expect(Rails.logger).to receive(:warn).with(/Invalid webhook signature.*enforced=false/)

        expect do
          post twilio_delivery_status_index_url, params: params, headers: { 'X-Twilio-Signature' => 'invalid' }
        end.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('delivery_status_signature_enforced')
      end

      it 'accepts a signature for the configured webhook URL when the request URL differs' do
        expect(Rails.logger).not_to receive(:warn).with(/Invalid webhook signature/)

        post '/twilio/delivery_status', params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
      end

      it 'logs query parameters added to a signed request' do
        expect(Rails.logger).to receive(:warn).with(/Invalid webhook signature.*enforced=false/)

        post '/twilio/delivery_status?Body=Tampered', params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
      end

      it 'does not mistake an API key secret for an account auth token' do
        channel.update!(api_key_sid: "SK#{SecureRandom.hex(16)}")
        expect(Rails.logger).to receive(:info).with(/Signature not verified, account auth token not configured/)

        post twilio_delivery_status_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('delivery_status_signature_enforced')
      end
    end
  end
end
