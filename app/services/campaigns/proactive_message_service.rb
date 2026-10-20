class Campaigns::ProactiveMessageService
  def initialize(campaign:)
    @campaign = campaign
  end

  # This response is shared by all visitors to the inbox. Never add a contact
  # or conversation to this context, even when the request has a widget token.
  def perform
    drops = Variables::ContextFactory.new(account: @campaign.account, records: { campaign: @campaign }).build(surface: 'campaign')
    Variables::DeliveryRenderer.new(drops: drops).render(@campaign.message, protect_code: true)
  rescue Variables::DeliveryRenderer::Error
    nil
  end
end
