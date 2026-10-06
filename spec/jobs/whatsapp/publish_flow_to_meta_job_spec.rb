require 'rails_helper'

RSpec.describe Whatsapp::PublishFlowToMetaJob do
  let(:account) { create(:account) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let!(:cloud_a) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:service) { instance_double(Whatsapp::Flows::PublishToMetaService, perform: { success: true, retryable: false }) }

  before { allow(Whatsapp::Flows::PublishToMetaService).to receive(:new).and_return(service) }

  def cloud_channel(waba_id)
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false).tap do |channel|
      channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => waba_id)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'is enqueued on the default queue' do
    expect { described_class.perform_later(flow.id, account.id) }.to have_enqueued_job(described_class).on_queue('default')
  end

  it 'publishes once per WABA: two numbers on the same WABA share it' do
    same_waba = cloud_channel(cloud_a.provider_config['business_account_id'])
    other_waba = cloud_channel('999000111')

    described_class.perform_now(flow.id, account.id)

    expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new).with(flow, cloud_a).once
    expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new).with(flow, other_waba).once
    expect(Whatsapp::Flows::PublishToMetaService).not_to have_received(:new).with(flow, same_waba)
  end

  it 'leaves non-Cloud channels out' do
    create(:channel_whatsapp, provider: 'default', account: account, validate_provider_config: false, sync_templates: false)

    described_class.perform_now(flow.id, account.id)

    expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new).once
  end

  it 'only publishes the given WABA on a retry' do
    other_waba = cloud_channel('999000111')

    described_class.perform_now(flow.id, account.id, '999000111')

    expect(Whatsapp::Flows::PublishToMetaService).to have_received(:new).with(flow, other_waba).once
    expect(Whatsapp::Flows::PublishToMetaService).not_to have_received(:new).with(flow, cloud_a)
  end

  it 'does not touch a flow of another account' do
    foreign = create(:whatsapp_flow)

    expect { described_class.perform_now(foreign.id, account.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not retry validation errors' do
    allow(service).to receive(:perform).and_return({ success: false, error: 'bad', retryable: false })

    expect { described_class.perform_now(flow.id, account.id) }.not_to have_enqueued_job(described_class)
  end

  it 'retries the run when Meta was unreachable for a WABA' do
    allow(service).to receive(:perform).and_return({ success: false, error: 'down', retryable: true })

    expect { described_class.perform_now(flow.id, account.id) }.to have_enqueued_job(described_class).with(flow.id, account.id)
  end
end
