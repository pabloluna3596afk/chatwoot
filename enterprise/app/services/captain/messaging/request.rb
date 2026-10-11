# What Captain asked to send: a Flow (resource: its id) or a template (resource: { name:, language: }), answering one
# customer message. `intro_text` is the text of a Flow message; `resend_requested` says the customer asked for the Flow
# that is still pending again.
class Captain::Messaging::Request < Struct.new(:kind, :resource, :responding_to_message_id, :intro_text, :resend_requested, keyword_init: true) # rubocop:disable Style/StructInheritance
  KINDS = %w[flow template].freeze
  INTRO_MAX_LENGTH = 1024

  def flow?
    kind == 'flow'
  end

  def valid?
    KINDS.include?(kind) && valid_resource? && valid_intro_text?
  end

  # What identifies the thing sent, in the audit record and in the fingerprint.
  def resource_key
    flow? ? resource.to_s : "#{resource[:name]}|#{resource[:language]}"
  end

  private

  def valid_resource?
    return resource.is_a?(Integer) if flow?

    resource.is_a?(Hash) && resource[:name].present? && resource[:language].present?
  end

  def valid_intro_text?
    intro_text.nil? || (flow? && intro_text.is_a?(String) && intro_text.present? && intro_text.length <= INTRO_MAX_LENGTH)
  end
end
