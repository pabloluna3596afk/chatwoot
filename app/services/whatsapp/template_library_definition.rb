# Library drafts keep a display-only preview. Submission resolves the authoritative text and buttons from Meta.
module Whatsapp::TemplateLibraryDefinition
  FIELDS = %w[template_name language button_inputs preview].freeze
  INPUT_BUTTON_TYPES = %w[PHONE_NUMBER URL].freeze

  def self.valid?(value)
    return false unless value.is_a?(Hash) && (value.keys - FIELDS).empty?
    return false unless identity_valid?(value)
    return false unless inputs_valid?(value.fetch('button_inputs', []))

    !value.key?('preview') || preview_valid?(value['preview'])
  end

  def self.identity_valid?(value)
    %w[template_name language].all? { |key| value[key].is_a?(String) && value[key].length <= (key == 'language' ? 20 : 512) }
  end

  def self.preview_valid?(value)
    value.is_a?(Hash) && (value.keys - %w[header body buttons]).empty? &&
      %w[header body].all? { |key| !value.key?(key) || (value[key].is_a?(String) && value[key].length <= 1024) } &&
      Whatsapp::TemplateDraftDefinition.buttons_valid?(value.fetch('buttons', []))
  end

  def self.inputs_valid?(inputs)
    inputs.is_a?(Array) && inputs.size <= 10 && inputs.all? { |input| input_valid?(input) }
  end

  def self.input_valid?(input)
    return false unless input.is_a?(Hash)

    case input['type']
    when 'PHONE_NUMBER'
      (input.keys - %w[type phone_number]).empty? && input['phone_number'].is_a?(String) && input['phone_number'].length <= 20
    when 'URL'
      (input.keys - %w[type url]).empty? && url_valid?(input['url'])
    else false
    end
  end

  def self.url_valid?(url)
    url.is_a?(Hash) && (url.keys - %w[base_url url_suffix_example]).empty? &&
      url['base_url'].is_a?(String) && url.values.all? { |item| item.is_a?(String) && item.length <= 2000 }
  end

  # Keep the same locale mapping as the existing library client.
  def self.language(value)
    Whatsapp::TemplateManagementService::LIBRARY_REGIONAL_LANGUAGES.include?(value) ? value : value.split('_').first
  end

  def self.same_language?(value, library_language)
    value.is_a?(String) && language(value) == language(library_language)
  end

  def self.validate_inputs!(inputs, buttons)
    required = buttons.select { |button| INPUT_BUTTON_TYPES.include?(button.fetch('type')) }
    valid = inputs.size == required.size && inputs.zip(required).all? { |input, button| complete_input?(input, button) }
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'invalid_buttons' unless valid
  end

  def self.complete_input?(input, button)
    return false unless input['type'] == button['type']
    return input['phone_number'].match?(/\A\+?[1-9]\d{6,14}\z/) if input['type'] == 'PHONE_NUMBER'

    input.dig('url', 'base_url').match?(%r{\Ahttps?://\S+\z}) &&
      (button.fetch('url', '').exclude?('{{') || input.dig('url', 'url_suffix_example').present?)
  end

  private_class_method :identity_valid?, :url_valid?
end
