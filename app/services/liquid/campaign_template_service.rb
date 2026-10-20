class Liquid::CampaignTemplateService
  pattr_initialize [:campaign!, :contact!]

  def call(message)
    drops = Variables::ContextFactory.new(account: campaign.account, records: { campaign: campaign, contact: contact }).build(surface: 'campaign')
    Variables::DeliveryRenderer.new(drops: drops).render(message, protect_code: true)
  end
end
