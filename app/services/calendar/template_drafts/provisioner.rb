class Calendar::TemplateDrafts::Provisioner
  def initialize(account:)
    @account = account
  end

  def status
    Calendar::TemplateDrafts::Status.new(account: @account).perform
  end

  def perform(language: nil)
    language ||= Calendar::TemplateDefinitions.language(@account)
    @account.with_lock do
      preparation = preparation_for(language)
      results = preparation.fetch('results')
      Calendar::TemplateDefinitions::FUNCTIONS.each_key do |function|
        next if %w[created reused].include?(results.dig(function, 'status'))

        results[function] = provision(function, language).merge('prepared_language' => language)
      end
      @account.update!(calendar_template_preparation: preparation)
    end
    status
  end

  private

  def preparation_for(language)
    preparation = (@account.calendar_template_preparation || {}).deep_dup
    languages = preparation.fetch('languages', {})
    languages[preparation.fetch('language')] ||= preparation.fetch('results') if preparation.key?('language')
    results = languages[language] ||= {}
    preparation.merge('language' => language, 'results' => results, 'languages' => languages)
  end

  def provision(function, language)
    name = Calendar::TemplateDefinitions::FUNCTIONS.fetch(function)
    resource = @account.calendar_template_resources.where(function: function, language: language).order(:id).first
    return existing_resource(resource) if resource

    drafts = @account.whatsapp_template_drafts.where(name: name, language: language).order(:id).to_a
    return conflict('multiple_drafts') if drafts.size > 1
    return reuse(function, language, drafts.first) if drafts.any?
    return conflict('remote_template_exists') if remote_name?(name, language)

    draft = create_draft(function, language, name)
    prepare_resource(function, language, draft, 'created')
  end

  def reuse(function, language, draft)
    return conflict('archived_draft', draft) if draft.archived_at?
    return conflict('missing_destination', draft) if draft.waba_id && !draft.destination_channels.exists?

    reason = draft_incompatibility(function, language, draft)
    return conflict(reason, draft) if reason

    prepare_resource(function, language, draft, 'reused')
  end

  def draft_incompatibility(function, language, draft)
    builder = Whatsapp::TemplateComponentsBuilder.new(**draft.definition.deep_symbolize_keys, parameter_format: draft.parameter_format)
    # This projection checks local content only. It never marks a draft as remotely approved.
    template = draft.attributes.slice('name', 'language', 'category', 'parameter_format')
                    .merge('id' => draft.id.to_s, 'status' => 'APPROVED', 'components' => builder.components.as_json)
    Calendar::TemplateContract.new(function: function, language: language, template: template).incompatibility
  rescue Whatsapp::TemplateComponentsBuilder::Invalid => e
    e.code
  end

  def create_draft(function, language, name)
    definition = Calendar::TemplateDefinitions.definition(function, language)
    @account.whatsapp_template_drafts.create!(
      name: name, language: language, category: Calendar::TemplateDefinitions::CATEGORY, parameter_format: 'NAMED',
      definition: { body: { text: definition.fetch(:body), examples: definition.fetch(:examples) },
                    buttons: definition.fetch(:buttons).map { |text| { type: 'QUICK_REPLY', text: text } } }
    )
  end

  def prepare_resource(function, language, draft, result)
    channel = draft.preferred_channel || draft.destination_channels.order(:id).first if draft.waba_id
    resource = Calendar::TemplateResources.new(account: @account, function: function, language: language, channel: channel)
                                          .prepare!(draft: draft)
    { 'status' => result, 'draft_id' => draft.id, 'resource_id' => resource.id }
  end

  def remote_name?(name, language)
    @account.whatsapp_channels.where(provider: 'whatsapp_cloud').any? do |channel|
      Array(channel.message_templates).any? { |template| template['name'] == name && template['language'] == language }
    end
  end

  def conflict(reason, draft = nil)
    { 'status' => 'conflict', 'reason' => reason, 'draft_id' => draft&.id }
  end

  def existing_resource(resource)
    conflict('existing_resource', resource.whatsapp_template_draft).merge('resource_id' => resource.id)
  end
end
