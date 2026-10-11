# What each variable of a WhatsApp template is filled with, chosen by an administrator when the template is made:
# { 'pedido' => 'contact.custom_attribute.pedido' }. Only the variables the shared table of names does not know
# ({{nombre}}, {{correo}}... see templateVariableBindings.js) need one; the rest are filled by their name.
#
# Meta replaces `message_templates` on every sync, so the choices live in `channel_whatsapp.template_variable_bindings`,
# by template name (the languages of a template share them), and are added to each template of the inbox payload.
class Whatsapp::TemplateVariableBindingsService
  VARIABLE = /\{\{\s*([^{}\s]+)\s*\}\}/
  SCOPES = %w[contact conversation agent account inbox appointment assistant].freeze
  KEY = /\A(#{SCOPES.join('|')})\.[a-z][a-z0-9_]*(\.[A-Za-z0-9_\-]+)?\z/
  MAX_KEY_LENGTH = 120

  class Invalid < StandardError; end

  def initialize(channel)
    @channel = channel
  end

  # The choices of a template, as { variable => key }.
  def for_template(name)
    stored[name.to_s].to_h
  end

  # The templates of the inbox with their `variable_bindings` (only the ones that have any).
  def merge_into(templates)
    Array(templates).map do |template|
      next template unless template.is_a?(Hash)

      bindings = for_template(template['name'])
      bindings.empty? ? template : template.merge('variable_bindings' => bindings)
    end
  end

  # The choices as they will be stored: { variable => key }. `texts` are the header and the body, whose variables are the
  # only ones that may have a choice. Raises Invalid, before anything is sent to Meta.
  def normalize(bindings, texts)
    return {} if bindings.blank?
    raise Invalid, 'variable_bindings must be an object' if bindings.is_a?(Array) || !bindings.respond_to?(:to_h)

    variables = Array(texts).flat_map { |text| text.to_s.scan(VARIABLE).flatten }.uniq
    bindings.to_h.to_h { |variable, key| [variable.to_s, key.to_s] }.each_with_object({}) do |(variable, key), clean|
      check(variable, key, variables)
      clean[variable] = key
    end
  end

  # Replaces the choices of a template with already normalized ones. Empty ones remove the entry.
  def store(name, clean)
    updated = stored.except(name.to_s)
    updated[name.to_s] = clean if clean.any?
    # Saved without validations: validate_provider_config checks the credentials with Meta, and nothing of the provider changes.
    @channel.template_variable_bindings = updated
    @channel.save!(validate: false)
  end

  private

  def check(variable, key, variables)
    raise Invalid, "variable #{variable} is not in the template" unless variables.include?(variable)
    raise Invalid, "variable #{variable} has an invalid value" unless key.length <= MAX_KEY_LENGTH && key.match?(KEY)
  end

  def stored
    @channel.template_variable_bindings.is_a?(Hash) ? @channel.template_variable_bindings : {}
  end
end
