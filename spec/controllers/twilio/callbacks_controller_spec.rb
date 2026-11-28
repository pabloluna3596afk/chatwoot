require 'rails_helper'

RSpec.describe 'Twilio::CallbacksController', type: :request do
  include Rails.application.routes.url_helpers

  describe 'POST /twilio/callback' do
    let(:params) do
      {
        'From' => '+1234567890',
        'To' => '+0987654321',
        'Body' => 'Test message',
        'AccountSid' => 'AC123',
        'SmsSid' => 'SM123',
        'ExternalUserId' => 'IN.2081978709342942',
        'ParentExternalUserId' => 'IN.ENT.9081726354',
        'ProfileUsername' => 'muhsin',
        'ReferralCtwaClid' => 'AfjyUDlaIoiweZDnlzmDTEaG',
        'ReferralSourceId' => '120237244350960485',
        'ReferralSourceUrl' => 'https://fb.me/4tBfhWhjr',
        'ReferralSourceType' => 'ad',
        'ReferralHeadline' => 'German citizenship lawyer',
        'ReferralBody' => 'Fast-track your German citizenship',
        'ReferralMediaId' => '',
        'ReferralNumMedia' => '0'
      }
    end

    it 'enqueues the Twilio events job' do
      expect do
        post twilio_callback_index_url, params: params
      end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
    end

    it 'returns no content status' do
      post twilio_callback_index_url, params: params
      expect(response).to have_http_status(:no_content)
    end

    it 'forwards the quoted message SID to the Twilio events job' do
      params['OriginalRepliedMessageSid'] = 'SMoriginal'

      expect do
        post twilio_callback_index_url, params: params
      end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
    end

    context 'when the request resolves to a channel' do
      let(:channel) { create(:channel_twilio_sms, :with_phone_number) }
      let(:params) do
        { 'From' => '+15550001111', 'To' => channel.phone_number, 'Body' => 'Hello', 'AccountSid' => channel.account_sid, 'SmsSid' => 'SM456' }
      end
      let(:signature) { Twilio::Security::RequestValidator.new(channel.auth_token).build_signature_for(twilio_callback_index_url, params) }

      it 'logs unsigned requests and still enqueues them' do
        expect(Rails.logger).to receive(:warn).with("[TWILIO] Invalid webhook signature channel_id=#{channel.id} endpoint=callback enforced=false")

        expect do
          post twilio_callback_index_url, params: params
        end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('callback_signature_enforced')
      end

      it 'accepts valid signatures without enabling enforcement' do
        expect(Rails.logger).not_to receive(:warn).with(/Invalid webhook signature/)

        expect do
          post twilio_callback_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }
        end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('callback_signature_enforced')
      end

      it 'continues logging invalid signatures after receiving a valid signature' do
        post twilio_callback_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }
        expect(Rails.logger).to receive(:warn).with(/Invalid webhook signature.*enforced=false/)

        expect do
          post twilio_callback_index_url, params: params, headers: { 'X-Twilio-Signature' => 'invalid' }
        end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('callback_signature_enforced')
      end

      it 'accepts a signature for the configured webhook URL when the request URL differs' do
        expect(Rails.logger).not_to receive(:warn).with(/Invalid webhook signature/)

        post '/twilio/callback', params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
      end

      it 'logs query parameters added to a signed request' do
        expect(Rails.logger).to receive(:warn).with(/Invalid webhook signature.*enforced=false/)

        post '/twilio/callback?Body=Tampered', params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
      end

      it 'verifies numbers in a messaging service pool against the phone number channel' do
        params['MessagingServiceSid'] = "MG#{SecureRandom.hex(16)}"
        expect(Rails.logger).not_to receive(:warn).with(/Invalid webhook signature/)

        expect do
          post twilio_callback_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }
        end.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
        expect(response).to have_http_status(:no_content)
      end

      it 'does not mistake an API key secret for an account auth token' do
        channel.update!(api_key_sid: "SK#{SecureRandom.hex(16)}")
        expect(Rails.logger).to receive(:info).with(/Signature not verified, account auth token not configured/)

        post twilio_callback_index_url, params: params, headers: { 'X-Twilio-Signature' => signature }

        expect(response).to have_http_status(:no_content)
        expect(channel.reload.provider_config).not_to have_key('callback_signature_enforced')
      end
    end
  end
end
