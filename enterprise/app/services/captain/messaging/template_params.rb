# Resolves Captain auto-mode template variables without samples or legacy dash fallbacks.
class Captain::Messaging::TemplateParams
  VARIABLE = Captain::TemplateMessage::VARIABLE

  def initialize(assistant, inbox, template)
    @assistant = assistant
    @inbox = inbox
    @template = template
  end

  # Returns [complete processed_params, missing variable names, variable sources].
  def resolve
    overrides = override_params
    bindings = Whatsapp::TemplateVariableBindingsService.new(@inbox.channel).for_template(@template['name'])
    variables = Captain::TemplateMessage.variables(@template)
    bindings = {} if binding_mismatch?(bindings, variables)
    params, sources = resolved_values(variables, overrides, bindings)

    [params, missing_variables(variables, params), sources]
  end

  private

  def resolved_values(variables, overrides, bindings)
    variables.each_with_object([{ 'body' => {}, 'header' => {} }, { 'body' => {}, 'header' => {} }]) do |variable, (params, sources)|
      value, source = resolve_variable(variable, overrides, bindings)
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

  def binding_mismatch?(bindings, variables)
    bindings.any? && bindings.keys.sort != variables.map(&:name).uniq.sort
  end

  def resolve_variable(variable, overrides, bindings)
    explicit, value = explicit_value(overrides, variable)
    return [valid_expression?(value) ? value : nil, 'assistant'] if explicit
    return [binding_expression(bindings[variable.name]), 'inbox'] if bindings.key?(variable.name)

    [alias_expression(variable.name), 'name']
  end

  def binding_expression(path)
    expression = "{{ #{path} }}"
    valid_expression?(expression) ? expression : nil
  end

  def alias_expression(name)
    return if name.match?(/\A\d+\z/)

    path = alias_path_for(name)
    "{{ #{path} }}" if path && catalog_paths.include?(path)
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

  def alias_path_for(name)
    return if name.match?(/\A\d+\z/)

    Variables::Catalog::ALIASES.each do |path, names|
      next if path.start_with?('appointment.')
      return path if names.include?(name)
    end
    nil
  end

  def catalog_paths
    @catalog_paths ||= Variables::Catalog.new(account: @assistant.account, surface: 'captain').as_json[:variables]
                                         .select { |variable| variable[:available] }
                                         .map { |variable| variable[:expression].delete_prefix('{{ ').delete_suffix(' }}') }
                                         .reject { |path| path.start_with?('appointment.') }
  end
end
