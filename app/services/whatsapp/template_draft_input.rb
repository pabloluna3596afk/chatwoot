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
end
