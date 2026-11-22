module Whatsapp::TemplateDraftInput
  def self.optional?(raw, key, type)
    !raw.key?(key) || raw[key].nil? || raw[key].is_a?(type)
  end

  def self.destination?(raw)
    optional?(raw, 'preferred_channel_id', Integer) && optional?(raw, 'waba_id', String)
  end

  def self.valid?(raw)
    return false unless raw.is_a?(ActionController::Parameters)
    return false unless destination?(raw)
    return false unless WhatsappTemplateDraft::STRING_LIMITS.keys.excluding(:source_remote_id).all? { |key| optional?(raw, key, String) }

    [:definition, :variable_bindings].all? { |key| !raw.key?(key) || raw[key].is_a?(ActionController::Parameters) }
  end

  def self.library_language_valid?(raw, draft)
    definition = raw.key?(:definition) ? raw[:definition].to_unsafe_h : draft&.definition
    return true unless definition.is_a?(Hash) && definition.key?('library')
    return false unless Whatsapp::TemplateDraftDefinition.valid?(definition)

    value = raw.fetch(:language) { draft&.language }
    Whatsapp::TemplateLibraryDefinition.same_language?(value, definition.fetch('library').fetch('language'))
  end
end
