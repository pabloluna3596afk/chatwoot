require 'rails_helper'

RSpec.describe Campaigns::SendWhatsappBatchJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:label) { create(:label, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }]) }

  before { account.enable_features!(:whatsapp_campaign) }

  it 'queues the first batch when a WhatsApp campaign starts' do
    expect { campaign.trigger! }.to have_enqueued_job(described_class).with(campaign)
    expect(campaign.reload).to be_processing
    expect(campaign.reload.whatsapp_cursor).to eq(0)
  end

  it 'advances the cursor between batches and completes after the last batch' do
    stub_const('Whatsapp::OneoffCampaignService::BATCH_SIZE', 1)
    contacts = create_list(:contact, 2, account: account)
    contacts.each { |contact| contact.update_labels([label.title]) }
    campaign.processing!
    campaign.update!(whatsapp_cursor: 0)
    service = Whatsapp::OneoffCampaignService.new(campaign: campaign)
    allow(Whatsapp::OneoffCampaignService).to receive(:new).and_return(service)
    allow(service).to receive(:process_contacts)

    expect { described_class.perform_now(campaign) }
      .to have_enqueued_job(described_class).with(campaign, contacts.first.id)
    expect(campaign.reload.whatsapp_cursor).to eq(contacts.first.id)
    expect(campaign.reload).to be_processing

    described_class.perform_now(campaign, contacts.first.id)
    expect(campaign.reload).to be_processing

    described_class.perform_now(campaign, contacts.last.id)
    expect(campaign.reload).to be_completed
  end

  it 'ignores completed campaigns' do
    campaign.completed!
    expect(Whatsapp::OneoffCampaignService).not_to receive(:new)

    described_class.perform_now(campaign)
  end
end
