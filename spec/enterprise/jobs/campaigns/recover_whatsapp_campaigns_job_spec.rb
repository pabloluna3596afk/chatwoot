require 'rails_helper'

RSpec.describe Campaigns::RecoverWhatsappCampaignsJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:campaign) { create(:campaign, account: account, inbox: channel.inbox) }

  it 're-enqueues a stale processing campaign from its saved cursor' do
    campaign.processing!
    campaign.update!(whatsapp_cursor: 123, updated_at: 16.minutes.ago)

    expect { described_class.perform_now }
      .to have_enqueued_job(Campaigns::SendWhatsappBatchJob).with(campaign, 123)
  end

  it 'ignores a processing campaign with no cursor' do
    campaign.processing!
    campaign.update!(whatsapp_cursor: nil, updated_at: 16.minutes.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Campaigns::SendWhatsappBatchJob)
  end

  it 'does not enable WhatsApp recovery for SMS campaigns' do
    sms = create(:channel_sms, account: account)
    sms_campaign = create(:campaign, account: account, inbox: sms.inbox)
    sms_campaign.processing!

    expect(sms_campaign.reload.whatsapp_cursor).to be_nil
  end
end
