# Saving permits missing content, but never coerces malformed JSON into form values.
module Whatsapp::TemplateDraftDefinition
  SECTIONS = { 'header' => %w[format text examples], 'body' => %w[text examples], 'footer' => %w[text] }.freeze
  BUTTON_FIELDS = %w[type text url phone_number code examples].freeze
  FIELD_LIMITS = { 'text' => 1024, 'url' => 2000, 'phone_number' => 20, 'code' => 15, 'type' => 40, 'format' => 40 }.freeze
  TEXT_LIMITS = { 'header' => 60, 'body' => 1024, 'footer' => 60 }.freeze

  def self.valid?(definition)
    if definition.is_a?(Hash) && definition.key?('library')
      return definition.keys == ['library'] && Whatsapp::TemplateLibraryDefinition.valid?(definition['library'])
    end

    return false unless definition.is_a?(Hash) && (definition.keys - [*SECTIONS.keys, 'buttons', 'preserved']).empty?

    sections_valid?(definition) && buttons_valid?(definition.fetch('buttons', [])) &&
      (!definition.key?('preserved') || preserved_valid?(definition['preserved']))
  end

  def self.sections_valid?(definition)
    SECTIONS.all? do |key, fields|
      !definition.key?(key) || (fields_valid?(definition[key], fields) && text_fits?(definition[key], TEXT_LIMITS.fetch(key)))
    end
  end

  def self.buttons_valid?(buttons)
    buttons.is_a?(Array) && buttons.size <= 10 && buttons.all? { |button| fields_valid?(button, BUTTON_FIELDS) && text_fits?(button, 25) }
  end

  def self.text_fits?(value, limit)
    !value.key?('text') || value.fetch('text').length <= limit
  end

  def self.fields_valid?(value, fields)
    value.is_a?(Hash) && (value.keys - fields).empty? && value.all? do |key, item|
      key == 'examples' ? examples_valid?(item) : item.is_a?(String) && item.length <= FIELD_LIMITS.fetch(key)
    end
  end

  def self.examples_valid?(examples)
    examples.is_a?(Array) && examples.size <= 100 && examples.all? { |example| example.is_a?(String) && example.length <= 2000 }
  end

  def self.preserved_valid?(value)
    return false unless value.is_a?(Hash) && (value.keys - %w[components buttons]).empty?

    value.all? do |group, entries|
      item_key = group == 'buttons' ? 'button' : 'component'
      entries.is_a?(Array) && entries.all? { |entry| preserved_entry_valid?(entry, item_key) }
    end
  end

  def self.preserved_entry_valid?(entry, item_key)
    return false unless entry.is_a?(Hash) && (entry.keys - ['position', item_key]).empty?
    return false unless entry['position'].is_a?(Integer) && entry['position'] >= 0

    entry[item_key].is_a?(Hash) && entry[item_key]['type'].is_a?(String)
  end
end
