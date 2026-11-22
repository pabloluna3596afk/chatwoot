class Whatsapp::TemplateDraftSourceService
  def initialize(account, actor, channel = nil)
    @account = account
    @actor = actor
    @channel = channel
  end

  def from_blueprint(id)
    blueprint = Whatsapp::BotTemplateBlueprintService::BLUEPRINTS[id]
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'unknown_blueprint' unless blueprint

    definition = { body: { text: blueprint.fetch(:body), examples: blueprint.fetch(:body_example).first },
                   buttons: blueprint.fetch(:buttons).map { |text| { type: 'QUICK_REPLY', text: text } } }
    attributes = blueprint.slice(:name, :language, :category).merge(parameter_format: 'POSITIONAL', definition: definition)
    create(attributes.merge(name: available_name(blueprint.fetch(:name), blueprint.fetch(:language))))
  end

  def from_library(attributes)
    validate_library_identity!(attributes)
    library = { template_name: attributes.fetch(:library_template_name), language: attributes.fetch(:language),
                button_inputs: attributes.fetch(:button_inputs, []) }
    library[:preview] = attributes[:preview] if attributes.key?(:preview)
    create(attributes.slice(:name, :language, :category).merge(parameter_format: 'POSITIONAL', definition: { library: library }))
  end

  private

  def validate_library_identity!(attributes)
    invalid = if attributes.fetch(:library_template_name).blank?
                'library_name_required'
              elsif !Whatsapp::TemplateComponentsBuilder.valid_name?(attributes.fetch(:name))
                'invalid_name'
              elsif !attributes.fetch(:language).match?(Api::V1::Accounts::InboxWhatsappTemplatesController::LANGUAGE_FORMAT)
                'invalid_language'
              elsif Whatsapp::TemplateComponentsBuilder::CATEGORIES.exclude?(attributes.fetch(:category))
                'invalid_category'
              end
    raise Whatsapp::TemplateComponentsBuilder::Invalid, invalid if invalid
  end

  def create(attributes)
    destination = @channel ? { preferred_channel: @channel, waba_id: @channel.provider_config.fetch('business_account_id') } : {}
    @account.whatsapp_template_drafts.create!(**attributes, **destination, created_by: @actor, updated_by: @actor)
  end

  def available_name(base, language)
    scope = @account.whatsapp_template_drafts.active.where(waba_id: @channel&.provider_config&.fetch('business_account_id'), language: language)
    candidate = base
    suffix = 1
    while scope.exists?(name: candidate) || remote_name?(candidate, language)
      suffix += 1
      candidate = "#{base}_#{suffix}"
    end
    candidate
  end

  def remote_name?(name, language)
    return false unless @channel

    @account.whatsapp_channels.where("provider_config ->> 'business_account_id' = ?", @channel.provider_config.fetch('business_account_id'))
            .any? { |channel| Array(channel.message_templates).any? { |entry| entry['name'] == name && entry['language'] == language } }
  end
end
