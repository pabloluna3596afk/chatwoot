class Whatsapp::TemplateLibrarySnapshotService
  def initialize(draft)
    @draft = draft
    @library = draft.definition.fetch('library')
    @language = Whatsapp::TemplateLibraryDefinition.language(draft.language)
  end

  def snapshot!
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'library_name_required' if @library.fetch('template_name').blank?

    template = find_template!
    inputs = @library.fetch('button_inputs', [])
    buttons = template.fetch('buttons', [])
    Whatsapp::TemplateLibraryDefinition.validate_inputs!(inputs, buttons)
    payload = { name: @draft.name, language: @language, category: @draft.category,
                library_template_name: @library.fetch('template_name'), button_inputs: inputs }.deep_stringify_keys
    { 'payload' => payload, 'preferred_channel_id' => @draft.preferred_channel_id, 'variable_bindings' => {},
      'library_definition' => { 'library' => @library.merge('language' => @language, 'preview' => preview(template)) },
      'reconciliation_payload' => { 'components' => components(template, inputs), 'parameter_format' => 'POSITIONAL' } }
  end

  private

  def find_template!
    client = Whatsapp::TemplateManagementService.new(@draft.destination_channels.order(:id).first, sync_after_change: false)
    after = nil
    loop do
      result = client.library(search: @library.fetch('template_name'), language: @language, after: after)
      template = result.fetch(:templates).find do |entry|
        entry['name'] == @library.fetch('template_name') && (entry['language'] || result[:language_used]) == @language
      end
      return template if template
      break if result.fetch(:templates).empty? || result[:next].blank?

      after = result.fetch(:next)
    end
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'invalid_language'
  end

  def preview(template)
    template.slice('header', 'body').merge('buttons' => template.fetch('buttons', []).map do |button|
      button.slice(*Whatsapp::TemplateDraftDefinition::BUTTON_FIELDS)
    end)
  end

  def components(template, inputs)
    result = []
    result << { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => template['header'] } if template['header'].present?
    result << { 'type' => 'BODY', 'text' => template.fetch('body') }
    remaining = inputs.deep_dup
    buttons = template.fetch('buttons', []).map do |button|
      item = button.slice('type', 'text', 'url', 'phone_number')
      input = remaining.shift if %w[PHONE_NUMBER URL].include?(button['type'])
      item['phone_number'] = input.fetch('phone_number') if button['type'] == 'PHONE_NUMBER'
      if button['type'] == 'URL'
        item['url'] = input.fetch('url').fetch('base_url')
        item['url'] += '{{1}}' if button.fetch('url', '').include?('{{')
      end
      item
    end
    result << { 'type' => 'BUTTONS', 'buttons' => buttons } if buttons.any?
    result
  end
end
