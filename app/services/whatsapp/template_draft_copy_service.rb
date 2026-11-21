class Whatsapp::TemplateDraftCopyService
  REMOTE_REFERENCE_KEY = /\A(?:id|handle)\z|_(?:id|handle)\z/

  def initialize(account, actor)
    @account = account
    @actor = actor
  end

  def duplicate(draft, destination)
    attributes = draft.attributes.slice('title', 'language', 'category', 'parameter_format', 'definition', 'variable_bindings')
    attributes['definition'] = local_definition(attributes.fetch('definition'))
    copy = WhatsappTemplateDraft.new(attributes.merge(destination).merge(account: @account, created_by: @actor, updated_by: @actor,
                                                                         source_draft: draft, name: suggested_name(draft.name)))
    copy.media = draft.media.blob if draft.media.attached?
    copy.tap(&:save!)
  end

  # Only the installed remote mirror is read: the installed template and its active bindings remain untouched.
  def from_remote(channel, remote_id)
    remote = Array(channel.message_templates).find { |template| template['id'] == remote_id }
    raise ActiveRecord::RecordNotFound unless remote

    submission = WhatsappTemplateSubmission.where(account: @account, remote_id: remote_id,
                                                  waba_id: channel.provider_config.fetch('business_account_id')).order(id: :desc).first
    library_definition = submission&.snapshot&.fetch('library_definition', nil)

    WhatsappTemplateDraft.create!(account: @account, created_by: @actor, updated_by: @actor, preferred_channel: channel,
                                  waba_id: channel.provider_config.fetch('business_account_id'), source_remote_id: remote_id,
                                  name: suggested_name(remote.fetch('name')), title: remote.fetch('name').first(100),
                                  language: remote.fetch('language'), category: remote.fetch('category'),
                                  parameter_format: remote['parameter_format'],
                                  definition: local_definition(library_definition || definition(remote.fetch('components'))))
  end

  private

  def local_definition(value)
    case value
    when Hash
      value.except(*value.keys.grep(REMOTE_REFERENCE_KEY))
           .transform_values { |item| local_definition(item) }
    when Array then value.map { |item| local_definition(item) }
    else value
    end
  end

  def suggested_name(original)
    base = original.presence || 'template'
    loop do
      candidate = "#{base.first(490)}_v_#{SecureRandom.hex(6)}"
      return candidate unless @account.whatsapp_template_drafts.exists?(name: candidate) ||
                              @account.whatsapp_channels.any? do |channel|
                                Array(channel.message_templates).any? do |entry|
                                  entry['name'] == candidate
                                end
                              end
    end
  end

  def definition(components)
    result = { 'preserved' => { 'components' => [], 'buttons' => [] } }
    components.each_with_index do |component, index|
      type = component['type']
      if %w[HEADER BODY FOOTER].include?(type)
        result[type.downcase] = section(component, type.downcase)
      elsif type == 'BUTTONS'
        result['buttons'] = []
        component.fetch('buttons').each_with_index { |button, position| copy_button(result, button, position) }
      else
        result['preserved']['components'] << { 'position' => index, 'component' => component.deep_dup }
      end
    end
    result
  end

  def section(component, key)
    result = component.slice('text', 'format')
    example = component.fetch('example', {})
    named = example["#{key}_text_named_params"]
    values = named ? named_examples(component, named) : example["#{key}_text"]
    result['examples'] = Array(key == 'body' && !named ? values&.first : values) if values
    result
  end

  def named_examples(component, named)
    examples = named.index_by { |entry| entry.fetch('param_name') }
    component.fetch('text').scan(Whatsapp::TemplateComponentsBuilder::VARIABLE).flatten.uniq.map { |name| examples.fetch(name).fetch('example') }
  end

  def copy_button(result, button, position)
    unless Whatsapp::TemplateComponentsBuilder::BUTTON_TYPES.include?(button['type'])
      result['preserved']['buttons'] << { 'position' => position, 'button' => button.deep_dup }
      return
    end
    copied = button.slice('type', 'text', 'url', 'phone_number')
    if button['type'] == 'COPY_CODE'
      copied['code'] = Array(button['example']).first if button['example']
    elsif button['example']
      copied['examples'] = Array(button['example'])
    end
    result['buttons'] << copied
  end
end
