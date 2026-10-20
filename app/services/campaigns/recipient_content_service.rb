class Campaigns::RecipientContentService
  pattr_initialize [:campaign!, :contact!]

  def perform
    Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
  rescue Variables::DeliveryRenderer::Error => e
    recipient = campaign.campaign_recipients.find_or_initialize_by(contact: contact)
    recipient.assign_attributes(account: campaign.account, inbox: campaign.inbox, phone_number: contact.phone_number)
    recipient.mark_skipped!(e.message)
    nil
  end
end
