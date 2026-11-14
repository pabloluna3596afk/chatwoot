# What of the conversation and the contact may reach the model, and in which shape.
class Captain::Assistant::PromptDataSanitizer
  MAX_VALUE_LENGTH = 200
  MAX_NAME_LENGTH = 80
  MAX_ATTRIBUTES = 25
  INTERNAL_PREFIX = 'captain_'.freeze
  CONVERSATION_ADDITIONAL_KEYS = %w[referer browser_language mail_subject type].freeze
  CONTACT_ADDITIONAL_KEYS = %w[city country country_code company_name description].freeze

  def self.conversation(data)
    return data if data.blank?

    data = data.with_indifferent_access
    data.merge(
      custom_attributes: attributes(data[:custom_attributes]),
      additional_attributes: attributes(data[:additional_attributes], only: CONVERSATION_ADDITIONAL_KEYS)
    )
  end

  def self.contact(data)
    return data if data.blank?

    data = data.with_indifferent_access
    data.merge(
      name: text(data[:name], MAX_NAME_LENGTH),
      email: text(data[:email], MAX_VALUE_LENGTH),
      identifier: text(data[:identifier], MAX_VALUE_LENGTH),
      custom_attributes: attributes(data[:custom_attributes]),
      additional_attributes: attributes(data[:additional_attributes], only: CONTACT_ADDITIONAL_KEYS)
    )
  end

  def self.attributes(hash, only: nil)
    hash.to_h.stringify_keys
        .reject { |key, _| key.start_with?(INTERNAL_PREFIX) }
        .select { |key, _| only.nil? || only.include?(key) }
        .first(MAX_ATTRIBUTES)
        .to_h { |key, value| [text(key, MAX_NAME_LENGTH), text(value, MAX_VALUE_LENGTH)] }
        .reject { |_, value| value.blank? }
  end

  def self.text(value, limit)
    return if value.nil?

    string = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
    string.gsub(/[[:cntrl:]]+/, ' ').squish.truncate(limit)
  end
end
