require 'rails_helper'

describe Whatsapp::IncomingMessageWhatsappCloudService do
  describe '#perform' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: inbox.account, inbox: inbox) }
    let!(:message) do
      create(:message, account: inbox.account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       source_id: 'wamid.pricing-message', additional_attributes: { 'existing' => 'preserved' })
    end
    let(:pricing) { { billable: false, pricing_model: 'PMP', type: 'free_customer_service', category: 'service' } }
    let(:status) do
      { id: message.source_id, status: 'delivered', timestamp: '1791244800', pricing: pricing }.with_indifferent_access
    end
    let(:params) { { entry: [{ changes: [{ value: { statuses: [status] } }] }] }.with_indifferent_access }
    let(:service) { described_class.new(inbox: inbox, params: params) }

    it 'stores delivered pricing with its status and integer timestamp, preserving other attributes' do
      service.perform

      expect(message.reload.additional_attributes).to eq(
        'existing' => 'preserved',
        'whatsapp_pricing' => {
          'billable' => false, 'pricing_model' => 'PMP', 'type' => 'free_customer_service', 'category' => 'service',
          'status' => 'delivered', 'at' => 1_791_244_800
        }
      )
      expect(message.status).to eq('delivered')
    end

    %w[sent read].each do |webhook_status|
      it "stores pricing carried by #{webhook_status}" do
        params[:entry][0][:changes][0][:value][:statuses][0][:status] = webhook_status

        service.perform

        expect(message.reload.additional_attributes['whatsapp_pricing']).to include('status' => webhook_status, 'billable' => false)
        expect(message.status).to eq(webhook_status)
      end
    end

    it 'retains pricing when a later read status omits it' do
      service.perform
      stored_pricing = message.reload.additional_attributes['whatsapp_pricing']
      params[:entry][0][:changes][0][:value][:statuses] = [{ id: message.source_id, status: 'read', timestamp: '1791244801' }]

      described_class.new(inbox: inbox, params: params).perform

      expect(message.reload.additional_attributes['whatsapp_pricing']).to eq(stored_pricing)
      expect(message.status).to eq('read')
    end

    it 'replaces pricing on a later read, preserving true and unknown category and type values' do
      service.perform
      params[:entry][0][:changes][0][:value][:statuses] = [{
        id: message.source_id, status: 'read', timestamp: '1791244801',
        pricing: { billable: true, pricing_model: 'PMP', type: 'future_type', category: 'future_category' }
      }]

      described_class.new(inbox: inbox, params: params).perform

      expect(message.reload.additional_attributes['whatsapp_pricing']).to eq(
        'billable' => true, 'pricing_model' => 'PMP', 'type' => 'future_type', 'category' => 'future_category',
        'status' => 'read', 'at' => 1_791_244_801
      )
    end

    it 'does not change the message when the same webhook arrives twice' do
      service.perform
      stored_attributes = message.reload.attributes

      described_class.new(inbox: inbox, params: params).perform

      expect(message.reload.attributes).to eq(stored_attributes)
    end

    it 'does nothing for an unknown source id' do
      params[:entry][0][:changes][0][:value][:statuses][0][:id] = 'wamid.unknown-pricing-message'
      stored_attributes = message.reload.attributes

      expect { service.perform }.not_to change(Message, :count)
      expect(message.reload.attributes).to eq(stored_attributes)
    end

    it 'does not add pricing when it is absent' do
      params[:entry][0][:changes][0][:value][:statuses][0].delete(:pricing)

      service.perform

      expect(message.reload.additional_attributes).to eq('existing' => 'preserved')
      expect(message.status).to eq('delivered')
    end

    it 'omits at when the webhook has no timestamp' do
      params[:entry][0][:changes][0][:value][:statuses][0].delete(:timestamp)

      service.perform

      expect(message.reload.additional_attributes['whatsapp_pricing']).to eq(
        'billable' => false, 'pricing_model' => 'PMP', 'type' => 'free_customer_service', 'category' => 'service',
        'status' => 'delivered'
      )
    end

    it 'does not store pricing on an incoming message' do
      message.update!(message_type: :incoming)

      service.perform

      expect(message.reload.additional_attributes).to eq('existing' => 'preserved')
    end

    it 'keeps the failed status and external error handling' do
      params[:entry][0][:changes][0][:value][:statuses] = [{
        id: message.source_id, status: 'failed', errors: [{ code: 131_047, title: 'Re-engagement message' }]
      }]

      service.perform

      expect(message.reload).to have_attributes(status: 'failed', external_error: '131047: Re-engagement message')
      expect(message.additional_attributes).to eq('existing' => 'preserved')
    end

    it 'leaves other providers unchanged even when their status carries pricing' do
      other_channel = create(:channel_whatsapp, provider: 'default', sync_templates: false, validate_provider_config: false)
      other_inbox = other_channel.inbox
      other_conversation = create(:conversation, account: other_inbox.account, inbox: other_inbox)
      other_message = create(:message, account: other_inbox.account, inbox: other_inbox, conversation: other_conversation,
                                       message_type: :outgoing, source_id: 'wamid.other-provider-message')
      other_params = { statuses: [{ id: other_message.source_id, status: 'delivered', pricing: pricing }] }.with_indifferent_access

      Whatsapp::IncomingMessageService.new(inbox: other_inbox, params: other_params).perform

      expect(other_message.reload.additional_attributes).not_to have_key('whatsapp_pricing')
      expect(other_message.status).to eq('delivered')
    end
  end
end
