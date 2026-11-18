module Api::V1::Accounts::InboxWhatsappTemplateVariableBindings
  extend ActiveSupport::Concern

  VARIABLE_BINDING_COMPONENTS = %w[BODY HEADER].freeze

  def variable_bindings
    name = params.require(:name)
    return render_error('invalid_variable_bindings') unless name.is_a?(String) && name.present?

    template = approved_template(name)
    return render_error('template_not_found', status: :not_found) unless template

    clean = normalize_request_bindings(template)
    variable_bindings_service.store(name, clean)
    render json: { name: name, variable_bindings: clean }
  rescue ActionController::ParameterMissing => e
    render json: { error: e.param, message: 'is required' }, status: :unprocessable_entity
  rescue Whatsapp::TemplateVariableBindingsService::Invalid => e
    render json: { error: 'invalid_variable_bindings', message: e.message }, status: :unprocessable_entity
  end

  private

  def approved_template(name)
    Array(@inbox.channel.message_templates).find do |entry|
      entry['name'] == name && entry['status'].to_s.casecmp?('APPROVED')
    end
  end

  def normalize_request_bindings(template)
    bindings = params.require(:variable_bindings)
    raise Whatsapp::TemplateVariableBindingsService::Invalid, 'bindings must be an object' unless bindings.is_a?(ActionController::Parameters)

    payload = bindings.to_unsafe_h
    unless payload.is_a?(Hash) && payload.values.all?(String)
      raise Whatsapp::TemplateVariableBindingsService::Invalid, 'bindings must contain text values'
    end

    variable_bindings_service.normalize(payload, template_binding_texts(template))
  end

  def template_binding_texts(template)
    Array(template['components']).filter_map do |component|
      type = component['type'].to_s.upcase
      allowed_binding_text?(component, type) ? component['text'] : nil
    end
  end

  def allowed_binding_text?(component, type)
    VARIABLE_BINDING_COMPONENTS.include?(type) && (type != 'HEADER' || component['format'].to_s.upcase == 'TEXT')
  end

  def variable_bindings_service
    @variable_bindings_service ||= Whatsapp::TemplateVariableBindingsService.new(@inbox.channel)
  end

  # The variables the administrator chose are validated before Meta is called.
  def prepare_variable_bindings
    return unless template_params.key?(:variable_bindings)
    raise Whatsapp::TemplateVariableBindingsService::Invalid, 'the template needs a name' if template_params[:name].blank?

    texts = [template_params.dig(:header, :text), template_params.dig(:body, :text)]
    @variable_bindings = variable_bindings_service.normalize(template_params[:variable_bindings].to_h, texts)
  rescue Whatsapp::TemplateVariableBindingsService::Invalid => e
    render_error('invalid_variable_bindings', message: e.message)
  end

  def store_variable_bindings(name)
    variable_bindings_service.store(name, @variable_bindings) unless @variable_bindings.nil?
  end
end
