# Turns the template form (header, body, footer, buttons as plain data) into the `components` Meta expects, and checks
# the rules Meta enforces so a mistake is shown before the template is sent for review (and not as a rejection later).
#
#   builder = Whatsapp::TemplateComponentsBuilder.new(
#     header: { format: 'TEXT', text: 'Hola {{nombre}}', examples: ['Ana'] },
#     body: { text: 'Tu cita es el {{fecha}}', examples: ['lunes'] },
#     footer: { text: 'Gracias' },
#     buttons: [{ type: 'QUICK_REPLY', text: 'Confirmar' }]
#   )
#   builder.components        # Meta's components
#   builder.parameter_format  # 'NAMED' ({{nombre}}) or 'POSITIONAL' ({{1}}): a template uses one of them
#
# Variables are named ({{nombre}}: lowercase letters, digits and underscores) or numbered ({{1}}, {{2}}, in order). The
# examples come in the order the variables first appear. Button URLs only take a numbered {{1}} at the end (Meta).
# The same limits are checked in the dashboard form (templateForm.js); keep them in step.
class Whatsapp::TemplateComponentsBuilder
  NAME_FORMAT = /\A[a-z0-9_]{1,512}\z/
  CATEGORIES = %w[UTILITY MARKETING].freeze
  HEADER_FORMATS = %w[NONE TEXT IMAGE VIDEO DOCUMENT].freeze
  MEDIA_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  BUTTON_TYPES = %w[QUICK_REPLY URL PHONE_NUMBER].freeze
  VARIABLE = /\{\{\s*([^{}\s]+)\s*\}\}/
  NUMBER = /\A\d+\z/
  NAMED_VARIABLE = /\A[a-z][a-z0-9_]*\z/
  URL_VARIABLE = /\{\{(\d+)\}\}/
  EDGE_VARIABLE = /\A\s*\{\{[^{}]+\}\}|\{\{[^{}]+\}\}\s*\z/
  LIMITS = { body: 1024, header_text: 60, footer: 60, button_text: 25, url: 2000, phone: 20, buttons: 10, url_buttons: 2, phone_buttons: 1 }.freeze

  # `code` is a stable key the API and the dashboard turn into a message; `details` completes it (field, limit...).
  class Invalid < StandardError
    attr_reader :code, :details

    def initialize(code, details = {})
      @code = code
      @details = details
      super("#{code} #{details}")
    end
  end

  def initialize(header: nil, body: nil, footer: nil, buttons: nil)
    @header = (header || {}).to_h.with_indifferent_access
    @body = (body || {}).to_h.with_indifferent_access
    @footer = (footer || {}).to_h.with_indifferent_access
    @buttons = Array(buttons).map { |button| button.to_h.with_indifferent_access }
  end

  def self.valid_name?(name)
    name.to_s.match?(NAME_FORMAT)
  end

  def components
    check_parameter_format
    [header_component, body_component, footer_component, buttons_component].compact
  end

  # 'NAMED' when the header or body use {{nombre}}-style variables, 'POSITIONAL' for {{1}} or none.
  def parameter_format
    named_variables? ? 'NAMED' : 'POSITIONAL'
  end

  private

  def all_tokens
    (variable_tokens(header_text_value) + variable_tokens(@body[:text].to_s)).uniq
  end

  def named_variables?
    all_tokens.any? { |token| !token.match?(NUMBER) }
  end

  # A template cannot mix {{1}} and {{nombre}}; named variables need a valid name.
  def check_parameter_format
    numbered, named = all_tokens.partition { |token| token.match?(NUMBER) }
    raise Invalid, 'variables_mixed' if numbered.any? && named.any?

    invalid = named.find { |token| !token.match?(NAMED_VARIABLE) }
    raise Invalid.new('variable_name_invalid', name: invalid) if invalid
  end

  def header_text_value
    @header[:format].to_s.upcase == 'TEXT' ? @header[:text].to_s : ''
  end

  def header_component
    format = (@header[:format].presence || 'NONE').to_s.upcase
    raise Invalid.new('invalid_header_format', format: format) unless HEADER_FORMATS.include?(format)
    return if format == 'NONE'
    return media_header(format) if MEDIA_FORMATS.include?(format)

    text_header
  end

  def text_header
    text = @header[:text].to_s.strip
    raise Invalid, 'header_text_required' if text.blank?
    raise Invalid.new('header_text_too_long', limit: LIMITS[:header_text]) if text.length > LIMITS[:header_text]

    tokens = variable_tokens(text)
    raise Invalid, 'header_one_variable' if tokens.size > 1 || (tokens.any? && !named_variables? && tokens.first != '1')

    component = { type: 'HEADER', format: 'TEXT', text: text }
    component[:example] = text_example(tokens, @header[:examples], 'header') if tokens.any?
    component
  end

  def media_header(format)
    handle = @header[:handle].to_s
    raise Invalid.new('header_media_required', format: format) if handle.blank?

    { type: 'HEADER', format: format, example: { header_handle: [handle] } }
  end

  def body_component
    text = @body[:text].to_s.strip
    tokens = variable_tokens(text)
    validate_body!(text, tokens)

    component = { type: 'BODY', text: text }
    component[:example] = text_example(tokens, @body[:examples], 'body') if tokens.any?
    component
  end

  def validate_body!(text, tokens)
    raise Invalid, 'body_required' if text.blank?
    raise Invalid.new('body_too_long', limit: LIMITS[:body]) if text.length > LIMITS[:body]
    raise Invalid, 'variables_not_sequential' if !named_variables? && tokens != (1..tokens.size).map(&:to_s)
    raise Invalid, 'variable_at_edge' if tokens.any? && text.match?(EDGE_VARIABLE)
  end

  # The sample values Meta asks for: a list for numbered variables, { param_name, example } pairs for named ones.
  def text_example(tokens, examples, field)
    values = required_example(examples, tokens.size, field)
    return { "#{field}_text": [field == 'header' ? values.first : values] } unless named_variables?

    { "#{field}_text_named_params": tokens.zip(values).map { |name, value| { param_name: name, example: value } } }
  end

  def footer_component
    text = @footer[:text].to_s.strip
    return if text.blank?
    raise Invalid.new('footer_too_long', limit: LIMITS[:footer]) if text.length > LIMITS[:footer]
    raise Invalid, 'footer_no_variables' if text.include?('{{')

    { type: 'FOOTER', text: text }
  end

  def buttons_component
    return if @buttons.empty?

    raise Invalid.new('too_many_buttons', limit: LIMITS[:buttons]) if @buttons.size > LIMITS[:buttons]

    built = @buttons.map { |button| build_button(button) }
    check_button_counts(built)
    { type: 'BUTTONS', buttons: built }
  end

  def build_button(button)
    type = button[:type].to_s.upcase
    raise Invalid.new('invalid_button_type', type: type) unless BUTTON_TYPES.include?(type)

    text = button[:text].to_s.strip
    raise Invalid, 'button_text_required' if text.blank?
    raise Invalid.new('button_text_too_long', limit: LIMITS[:button_text]) if text.length > LIMITS[:button_text]

    case type
    when 'URL' then url_button(text, button)
    when 'PHONE_NUMBER' then phone_button(text, button)
    else { type: type, text: text }
    end
  end

  def url_button(text, button)
    url = button[:url].to_s.strip
    raise Invalid, 'url_invalid' unless url.match?(%r{\Ahttps?://\S+\z}) && url.length <= LIMITS[:url]

    numbers = url.scan(URL_VARIABLE).flatten.uniq
    raise Invalid, 'url_variable_at_end' if url.include?('{{') && (numbers.size != 1 || !url.end_with?('{{1}}'))

    built = { type: 'URL', text: text, url: url }
    built[:example] = [required_example(button[:examples], 1, 'url')[0]] if numbers.any?
    built
  end

  def phone_button(text, button)
    phone = button[:phone_number].to_s.strip
    raise Invalid, 'phone_invalid' unless phone.match?(/\A\+\d{6,18}\z/)

    { type: 'PHONE_NUMBER', text: text, phone_number: phone }
  end

  def check_button_counts(built)
    raise Invalid.new('too_many_url_buttons', limit: LIMITS[:url_buttons]) if built.count { |b| b[:type] == 'URL' } > LIMITS[:url_buttons]
    return unless built.count { |b| b[:type] == 'PHONE_NUMBER' } > LIMITS[:phone_buttons]

    raise Invalid.new('too_many_phone_buttons', limit: LIMITS[:phone_buttons])
  end

  # The variables of a text, in order of first appearance and without repeats ("1", "2" or "nombre", "fecha").
  def variable_tokens(text)
    text.to_s.scan(VARIABLE).flatten.uniq
  end

  # Meta rejects a template whose variables have no sample value, so each one needs a non empty example.
  def required_example(examples, count, field)
    list = Array(examples).map { |example| example.to_s.strip }
    raise Invalid.new('example_required', field: field) if list.size < count || list.first(count).any?(&:blank?)

    list.first(count)
  end
end
