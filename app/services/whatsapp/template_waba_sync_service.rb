class Whatsapp::TemplateWabaSyncService
  def initialize(account, waba_id)
    @account = account
    @waba_id = waba_id
  end

  def perform
    channels = @account.whatsapp_channels.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", @waba_id)
    channel = channels.order(:id).first!
    templates = Whatsapp::TemplateManagementService.new(channel).templates
    channels.transaction do
      # Bulk update avoids Channel::Whatsapp's remote credential-validation callback. The data is solely Meta's mirror.
      channels.update_all(message_templates: templates, message_templates_last_updated: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      @account.update_cache_key('inbox')
    end
    Calendar::TemplateDrafts::AutoLinker.new(account: @account, waba_id: @waba_id).perform
  end
end
