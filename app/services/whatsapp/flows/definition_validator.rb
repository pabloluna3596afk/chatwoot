# Checks a ChatHub form definition (see Whatsapp::Flows::Spec) against the rules Meta enforces, so a mistake shows up
# while the form is being built and not as a refusal when it is published.
#
#   result = Whatsapp::Flows::DefinitionValidator.new(definition).call
#   result.valid?   # no errors
#   result.errors   # [{ code: 'label_too_long', path: 'screens.0.blocks.2.label', details: { limit: 20 } }]
#
# `path` points into the definition so the builder can mark the field.
class Whatsapp::Flows::DefinitionValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end
  end

  Spec = Whatsapp::Flows::Spec

  def initialize(definition, account: nil)
    @account = account
    @save_targets = []
    @definition = Spec.string_keys(definition.is_a?(Hash) ? definition : {})
    @errors = []
    @warnings = []
  end

  def call
    screens = @definition['screens']
    if screens.is_a?(Array) && screens.any?
      check_screens(screens)
    else
      add('screens_required', 'screens')
    end
    Result.new(@errors, @warnings)
  end

  private

  def check_screens(screens)
    add('too_many_screens', 'screens', limit: Spec::LIMITS[:screens]) if screens.size > Spec::LIMITS[:screens]
    screens.each_with_index { |screen, index| check_screen(screen, index) }
    check_keys
    check_conditions
  end

  def add(code, path, details = {})
    @errors << { code: code, path: path, details: details }
  end

  def check_screen(screen, index)
    path = "screens.#{index}"
    title = screen['title'].to_s.strip
    add('screen_title_required', "#{path}.title") if title.empty?
    add('screen_title_too_long', "#{path}.title", limit: Spec::LIMITS[:screen_title]) if title.length > Spec::LIMITS[:screen_title]
    check_button(screen, path)
    blocks = screen['blocks']
    return add('blocks_required', "#{path}.blocks") unless blocks.is_a?(Array) && blocks.any?

    check_screen_totals(blocks, path)
    blocks.each_with_index { |block, block_index| check_block(block, "#{path}.blocks.#{block_index}") }
  end

  def check_button(screen, path)
    label = screen['button'].to_s.strip
    add('button_required', "#{path}.button") if label.empty?
    add('button_too_long', "#{path}.button", limit: Spec::LIMITS[:footer]) if label.length > Spec::LIMITS[:footer]
    add('button_no_emoji', "#{path}.button") if label.match?(Spec::EMOJI)
  end

  # Meta: 50 components per screen (the footer counts), 5 opt-ins, one file picker of each kind.
  def check_screen_totals(blocks, path)
    max = Spec::LIMITS[:components_per_screen] - 1
    add('too_many_components', "#{path}.blocks", limit: max) if blocks.size > max
    optins = blocks.count { |block| block['type'] == 'optin' }
    add('too_many_optins', "#{path}.blocks", limit: Spec::LIMITS[:optins_per_screen]) if optins > Spec::LIMITS[:optins_per_screen]
    Spec::FILE_BLOCKS.each do |type|
      next unless blocks.count { |block| block['type'] == type } > Spec::LIMITS[:file_blocks_per_screen]

      add('too_many_file_blocks', "#{path}.blocks", type: type, limit: Spec::LIMITS[:file_blocks_per_screen])
    end
  end

  def check_block(block, path)
    return add('block_invalid', path) unless block.is_a?(Hash) && Spec::BLOCK_TYPES.include?(block['type'])

    check_save_to(block, path) if block.key?('save_to')

    if Spec::TEXT_BLOCKS.include?(block['type'])
      check_text(block, path)
    else
      check_input(block, path)
    end
  end

  def check_save_to(block, path)
    mapping = block['save_to']
    return add('save_to_invalid', "#{path}.save_to") unless mapping.is_a?(Hash) && mapping.keys == ['target']

    target = mapping['target']
    return add('save_to_incompatible', "#{path}.save_to") unless Whatsapp::Flows::SaveTargets.compatible?(block, target, @account)

    add('save_to_duplicate', "#{path}.save_to") if @save_targets.include?(target)
    @save_targets << target
  end

  def check_text(block, path)
    text = block['text'].to_s.strip
    limit = Spec::LIMITS[Spec::TEXT_LIMITS[block['type']]]
    add('text_required', "#{path}.text") if text.empty?
    add('text_too_long', "#{path}.text", limit: limit) if text.length > limit
  end

  def check_input(block, path)
    type = block['type']
    check_label(block, path)
    add('helper_too_long', "#{path}.helper", limit: Spec::LIMITS[:helper]) if block['helper'].to_s.length > Spec::LIMITS[:helper]
    check_text_input(block, path) if type == 'short_text'
    check_options(block, path) if Spec::OPTION_BLOCKS.include?(type)
    check_files(block, path) if Spec::FILE_BLOCKS.include?(type)
  end

  def check_text_input(block, path)
    return if block['input'].blank? || Spec::TEXT_INPUTS.include?(block['input'])

    add('input_invalid', "#{path}.input")
  end

  def check_label(block, path)
    label = block['label'].to_s.strip
    limit = Spec::LIMITS[Spec::LABEL_LIMITS[block['type']]]
    add('label_required', "#{path}.label") if label.empty?
    add('label_too_long', "#{path}.label", limit: limit) if label.length > limit
  end

  def check_options(block, path)
    options = block['options']
    return add('options_required', "#{path}.options") unless options.is_a?(Array) && options.any?

    limit = options_limit(block)
    add('too_many_options', "#{path}.options", limit: limit) if options.size > limit
    options.each_with_index { |option, index| check_option(option, "#{path}.options.#{index}") }
    ids = option_ids(block)
    add('option_ids_duplicate', "#{path}.options") if ids.uniq.size != ids.size
    check_selection_range(block, path)
  end

  def options_limit(block)
    Spec::LIMITS[block['type'] == 'dropdown' ? :dropdown_options : :options]
  end

  def check_option(option, path)
    return add('option_invalid', path) unless option.is_a?(Hash)

    add('option_id_invalid', "#{path}.id") unless option['id'].to_s.match?(Spec::OPTION_ID_FORMAT)
    title = option['title'].to_s.strip
    add('option_title_required', "#{path}.title") if title.empty?
    add('option_title_too_long', "#{path}.title", limit: Spec::LIMITS[:option_title]) if title.length > Spec::LIMITS[:option_title]
  end

  def check_selection_range(block, path)
    return unless block['type'] == 'checkbox'

    min = block['min'].to_i
    max = block['max'].to_i
    count = Array(block['options']).size
    invalid = min.negative? || min > count || (max.positive? && (max < min || max > count))
    add('selection_range_invalid', "#{path}.min") if invalid
  end

  def check_files(block, path)
    max = block['max_files'].to_i
    min = block['min_files'].to_i
    limit = Spec::LIMITS[:files_per_block]
    invalid = max.negative? || max > limit || min.negative? || (max.positive? && min > max)
    add('files_range_invalid', "#{path}.max_files", limit: limit) if invalid
  end

  # Every answer needs a name that is unique in the whole form: it is the name Meta sends it back with.
  def check_keys
    seen = {}
    Spec.fields(@definition).each do |field|
      path = "screens.#{field[:screen]}.blocks.#{field[:block]}.key"
      next add('key_invalid', path) unless field[:key].match?(Spec::KEY_FORMAT)
      next add('key_duplicate', path) if seen[field[:key]]

      seen[field[:key]] = field
    end
  end

  # A condition looks at one earlier answer that is a single value; its value has to be one the answer can have.
  def check_conditions
    fields = Spec.fields(@definition).select { |field| field[:key].match?(Spec::KEY_FORMAT) }
    Array(@definition['screens']).each_with_index do |screen, screen_index|
      Array(screen['blocks']).each_with_index do |block, block_index|
        condition = block['visible_when'] if block.is_a?(Hash)
        next if condition.blank?

        check_condition(condition, "screens.#{screen_index}.blocks.#{block_index}.visible_when", [screen_index, block_index], fields)
      end
    end
  end

  def check_condition(condition, path, position, fields)
    return add('condition_invalid', path) unless condition.is_a?(Hash) && %w[equals not_equals].include?(condition['op'])

    source = fields.find { |field| field[:key] == condition['key'].to_s }
    return add('condition_unknown_field', "#{path}.key") if source.nil?
    return add('condition_not_earlier', "#{path}.key") unless ([source[:screen], source[:block]] <=> position).negative?
    return add('condition_field_unsupported', "#{path}.key", type: source[:type]) unless Spec::CONDITION_KINDS.include?(source[:type])

    check_condition_value(condition, path, source)
  end

  def check_condition_value(condition, path, source)
    value = condition['value'].to_s
    valid = case source[:type]
            when 'dropdown', 'radio' then option_ids(source[:definition]).include?(value)
            when 'optin' then %w[true false].include?(value)
            else value.match?(Spec::CONDITION_VALUE_FORMAT)
            end
    add('condition_value_invalid', "#{path}.value") unless valid
  end

  def option_ids(block)
    Array(block['options']).filter_map { |option| option['id'] if option.is_a?(Hash) }
  end
end
