# Resolves Captain template variables, reading legacy values before the shared inbox sources.
class Captain::Messaging::TemplateParams
  def initialize(assistant, inbox, template)
    @assistant = assistant
    @inbox = inbox
    @template = template
  end

  # Returns [complete processed_params, missing variable names, variable sources].
  def resolve
    legacy = @assistant.messaging.mode(@inbox.id) == 'list'
    overrides = if legacy
                  @assistant.messaging.template(@inbox.id, @template['name'], @template['language'])&.fetch('processed_params', nil).to_h
                else
                  override_params
                end
    bindings = Whatsapp::TemplateVariableSources.new(@inbox.channel).for(@template)
    variables = Captain::TemplateMessage.variables(@template)
    params, sources = resolved_values(variables, overrides, bindings, legacy)

    missing = legacy ? Captain::TemplateMessage.unmapped(@template, params) : missing_variables(variables, params)
    [params, missing, sources]
  end

  private

  def resolved_values(variables, overrides, bindings, legacy)
    variables.each_with_object([{ 'body' => {}, 'header' => {} }, { 'body' => {}, 'header' => {} }]) do |variable, (params, sources)|
      value, source = resolve_variable(variable, overrides, bindings, legacy)
      next unless value

      params[variable.component][variable.name] = value
      sources[variable.component][variable.name] = source
    end
  end

  def missing_variables(variables, params)
    variables.reject { |variable| params[variable.component].key?(variable.name) }.map(&:name).uniq
  end

  def override_params
    waba_id = @inbox.channel.provider_config.to_h['business_account_id'].to_s
    key = Captain::Messaging::TemplateKey.for(waba_id, @template)
    @assistant.messaging.params_for(@inbox.id, key).to_h
  end

  def resolve_variable(variable, overrides, bindings, legacy)
    explicit, value = explicit_value(overrides, variable)
    if explicit
      return [valid_expression?(value) ? value : nil, 'assistant'] unless legacy
      return [value, 'legacy'] if value.present?
    end

    source = bindings.fetch(variable.component).fetch(variable.name)
    [source[:path] && "{{ #{source[:path]} }}", source[:source]]
  end

  def explicit_value(params, variable)
    component = params[variable.component]
    return [false, nil] unless component.is_a?(Hash) && component.key?(variable.name)

    [true, component[variable.name].to_s]
  end

  def valid_expression?(value)
    match = /\A\{\{\s*([^{}]+?)\s*\}\}\z/.match(value.to_s)
    path = match && match[1].strip
    return false unless path

    catalog_paths.include?(path)
  end

  def catalog_paths
    @catalog_paths ||= Variables::Catalog.new(account: @assistant.account, surface: 'captain').as_json[:variables]
                                         .select { |variable| variable[:available] }
                                         .map { |variable| variable[:expression].delete_prefix('{{ ').delete_suffix(' }}') }
                                         .reject { |path| path.start_with?('appointment.') }
  end
end
