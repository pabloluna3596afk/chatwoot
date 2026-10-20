class Whatsapp::LiquidTemplateProcessorService
  pattr_initialize [:campaign!, :contact!]

  attr_reader :resolution_error

  def process_template_params(template_params)
    @resolution_error = nil
    return template_params if template_params.blank?

    copy = template_params.deep_dup
    return copy if copy['processed_params'].blank?

    drops = Variables::ContextFactory.new(account: campaign.account, records: { campaign: campaign, contact: contact }).build(surface: 'campaign')
    copy.merge('processed_params' => Variables::DeliveryRenderer.new(drops: drops).render(copy['processed_params'], path: 'processed_params'))
  rescue Variables::DeliveryRenderer::Error => e
    @resolution_error = e.message
    nil
  end
end
