module Whatsapp::Flows::SaveTargets
  STANDARD = %w[contact.name contact.email contact.phone contact.company_name contact.city contact.document_number].freeze
  CUSTOM_PREFIX = 'contact.custom_attribute.'.freeze
  ALLOWED_TYPES = {
    'short_text' => %w[text number].freeze,
    'long_text' => %w[text].freeze,
    'checkbox' => %w[text].freeze,
    'date' => %w[date text].freeze,
    'optin' => %w[checkbox].freeze,
    'dropdown' => %w[text list].freeze,
    'radio' => %w[text list].freeze
  }.freeze

  module_function

  def attribute(account, target)
    return unless account && target.start_with?(CUSTOM_PREFIX)

    account.custom_attribute_definitions.contact_attribute.find_by(attribute_key: target.delete_prefix(CUSTOM_PREFIX))
  end

  def compatible?(block, target, account)
    return false unless target.is_a?(String)

    custom = attribute(account, target)
    return false unless writable_target?(target, custom)

    type = custom ? custom.attribute_display_type : 'text'
    return false unless ALLOWED_TYPES.fetch(block['type'], []).include?(type)

    compatible_constraints?(block, type, custom)
  end

  def writable_target?(target, custom)
    (STANDARD.include?(target) || custom) && !custom&.formula?
  end

  def compatible_constraints?(block, type, custom)
    return block['input'] == 'number' if block['type'] == 'short_text' && type == 'number'
    return compatible_options?(block, custom) if type == 'list'

    true
  end

  private_class_method :writable_target?, :compatible_constraints?

  def compatible_options?(block, custom)
    Array(block['options']).all? do |option|
      option.is_a?(Hash) && Array(custom.attribute_values).include?(option['id'])
    end
  end
end
