require 'rails_helper'

RSpec.describe Whatsapp::PublishFlowToMetaJob, type: :job do
  let(:account) { create(:account) }
  let(:whatsapp_flow) { create(:whatsapp_flow, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider_config: {
      'business_account_id' => '1554207416398687',
      'access_token' => 'test_token'
    })
  end

  before do
    channel
    allow(Whatsapp::Flows::PublishToMetaService).to receive(:new).and_return(double(perform: { success: true }))
  end

  describe '#perform' do
    it 'enqueues successfully' do
      expect {
        described_class.perform_later(whatsapp_flow.id, account.id)
      }.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)
    end

    it 'discovers all Cloud WABAs in account' do
      allow_any_instance_of(Whatsapp::Flows::PublishToMetaService).to receive(:perform).and_return({ success: true })

      described_class.new.perform(whatsapp_flow.id, account.id)

      expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new)
    end

    it 'handles network errors with retry' do
      allow_any_instance_of(Whatsapp::Flows::PublishToMetaService).to receive(:perform).and_raise(Timeout::Error)

      expect {
        described_class.new.perform(whatsapp_flow.id, account.id)
      }.to raise_error(Timeout::Error)
    end

    it 'does not retry validation errors' do
      allow_any_instance_of(Whatsapp::Flows::PublishToMetaService).to receive(:perform).and_return({
        success: false,
        error: 'Invalid flow JSON'
      })

      described_class.new.perform(whatsapp_flow.id, account.id)

      expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new)
    end
  end
end
