# The ChatHub form ("flow") definition: a neutral, channel-independent description that is exported to Meta's Flow JSON
# (Whatsapp::Flows::Exporter), shown in the dashboard preview, and can be rendered by the CRM itself.
#
#   {
#     'schema_version' => 1,
#     'screens' => [
#       { 'title' => 'Tus datos', 'button' => 'Continuar',
#         'blocks' => [
#           { 'type' => 'heading', 'text' => 'Hola' },
#           { 'type' => 'short_text', 'key' => 'nombre', 'label' => 'Nombre', 'required' => true, 'input' => 'text' },
#           { 'type' => 'dropdown', 'key' => 'tipo', 'label' => 'Tipo', 'options' => [{ 'id' => 'a', 'title' => 'A' }] },
#           { 'type' => 'short_text', 'key' => 'detalle', 'label' => 'Detalle',
#             'visible_when' => { 'key' => 'tipo', 'op' => 'equals', 'value' => 'a' } }
#         ] }
#     ]
#   }
#
# Screens follow one another in the order of the list; the last one completes the form. A block can be shown or hidden
# by the answer to a field that comes before it (`visible_when`, one condition). Meta limits are those of Flow JSON 7.3.
#
# The limits, the Flow JSON structure and the rules were checked against Meta's documentation and adapted from the MIT
# licensed projects gokapso/flowso (validator, Copyright (c) 2026 Kapso) and ANGELBERRIOS23/whatsapp-flow-studio
# (builder and gotchas, Copyright (c) 2026 Angel Berríos); see the notice in Whatsapp::Flows::FlowJsonValidator.
module Whatsapp::Flows::Spec
  # Input blocks may have save_to: { 'target' => 'contact.email' }. This CRM metadata is never exported to Meta.
  SCHEMA_VERSION = 1
  FLOW_JSON_VERSION = '7.3'.freeze

  TEXT_BLOCKS = %w[heading subheading text caption].freeze
  INPUT_BLOCKS = %w[short_text long_text dropdown radio checkbox date optin photo document].freeze
  OPTION_BLOCKS = %w[dropdown radio checkbox].freeze
  FILE_BLOCKS = %w[photo document].freeze
  BLOCK_TYPES = (TEXT_BLOCKS + INPUT_BLOCKS).freeze
  # What a `visible_when` can look at: a single answer (not a list or a file).
  CONDITION_KINDS = %w[short_text dropdown radio optin].freeze
  TEXT_INPUTS = %w[text email phone number].freeze
  # Meta's categories for a flow.
  CATEGORIES = %w[SIGN_UP SIGN_IN APPOINTMENT_BOOKING LEAD_GENERATION CONTACT_US CUSTOMER_SUPPORT SURVEY OTHER].freeze

  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,39}\z/
  OPTION_ID_FORMAT = /\A[a-z0-9_]{1,40}\z/
  # No quote or backslash: the value goes inside a Flow JSON expression.
  CONDITION_VALUE_FORMAT = /\A[^'"\\$]{1,40}\z/
  EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/

  LIMITS = {
    screens: 20, components_per_screen: 50, screen_title: 30, footer: 35, heading: 80, subheading: 80, text: 4096, caption: 409,
    key_label: 20, choice_label: 30, date_label: 40, optin_label: 120, file_label: 80, helper: 80,
    option_title: 30, options: 20, dropdown_options: 200, optins_per_screen: 5, files_per_block: 30, file_blocks_per_screen: 1
  }.freeze

  LABEL_LIMITS = {
    'short_text' => :key_label, 'long_text' => :key_label, 'dropdown' => :key_label, 'radio' => :choice_label,
    'checkbox' => :choice_label, 'date' => :date_label, 'optin' => :optin_label, 'photo' => :file_label, 'document' => :file_label
  }.freeze
  TEXT_LIMITS = { 'heading' => :heading, 'subheading' => :subheading, 'text' => :text, 'caption' => :caption }.freeze

  DEFAULT_MIME_TYPES = %w[application/pdf image/jpeg image/png application/msword
                          application/vnd.openxmlformats-officedocument.wordprocessingml.document].freeze

  module_function

  # [{ screen:, index:, block:, key:, type: }] for every block that collects an answer, in order.
  def fields(definition)
    Array(definition['screens']).each_with_index.flat_map do |screen, screen_index|
      Array(screen['blocks']).each_with_index.filter_map do |block, block_index|
        next unless INPUT_BLOCKS.include?(block['type'])

        { screen: screen_index, block: block_index, key: block['key'].to_s, type: block['type'], definition: block }
      end
    end
  end

  # Letters and underscores only, so a screen id is accepted whatever the exact rule of Meta is: PANTALLA_A, PANTALLA_B...
  def screen_id(index)
    "PANTALLA_#{letters(index)}"
  end

  def letters(index)
    result = +''
    number = index
    loop do
      result.prepend(('A'.ord + (number % 26)).chr)
      number = (number / 26) - 1
      break if number.negative?
    end
    result
  end

  def string_keys(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_s, string_keys(item)] }
    when Array then value.map { |item| string_keys(item) }
    else value
    end
  end
end
