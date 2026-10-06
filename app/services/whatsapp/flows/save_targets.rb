module Whatsapp::Flows::SaveTargets
  STANDARD = %w[contact.name contact.email contact.phone contact.company_name contact.city contact.document_number].freeze
  CUSTOM_PREFIX = 'contact.custom_attribute.'.freeze

  module_function

  def attribute(account, target)
    return unless account && target.start_with?(CUSTOM_PREFIX)

    account.custom_attribute_definitions.contact_attribute.find_by(attribute_key: target.delete_prefix(CUSTOM_PREFIX))
  end

  def compatible?(block, target, account)
    return false unless target.is_a?(String)

    custom = attribute(account, target)
    return false unless STANDARD.include?(target) || custom
    return false if custom&.formula?

    type = custom ? custom.attribute_display_type : 'text'
    case block['type']
    when 'short_text' then type == 'text' || (block['input'] == 'number' && type == 'number')
    when 'long_text', 'checkbox' then type == 'text'
    when 'date' then %w[date text].include?(type)
    when 'optin' then type == 'checkbox'
    when 'dropdown', 'radio'
      type == 'text' || (type == 'list' && compatible_options?(block, custom))
    else false
    end
  end

  def compatible_options?(block, custom)
    Array(block['options']).all? do |option|
      option.is_a?(Hash) && Array(custom.attribute_values).include?(option['id'])
    end
  end
end
