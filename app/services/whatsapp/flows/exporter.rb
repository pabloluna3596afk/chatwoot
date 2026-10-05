# Turns a ChatHub form definition (see Whatsapp::Flows::Spec) into Meta's Flow JSON 7.3, for a static flow (no endpoint).
#
#   Whatsapp::Flows::Exporter.new(definition).call  # => { 'version' => '7.3', 'screens' => [...] }
#
# What it takes care of, which is where hand-written Flow JSON usually breaks:
#   - every screen is one SingleColumnLayout with one Form holding the blocks and the Footer;
#   - screens follow the order of the list: each Footer navigates to the next screen, the last one completes the flow;
#   - data travels from screen to screen: a screen declares in `data` every answer given before it and its Footer passes
#     on everything collected so far (navigate payloads must cover all the `data` keys of the next screen);
#   - the final `complete` payload holds every answer, under the key the form gave it;
#   - a block with `visible_when` is wrapped in an If on the answer (`${form.x}` on the same screen, `${data.x}` before);
#   - screen ids are PANTALLA_A, PANTALLA_B... (letters and underscore only).
#
# Based on the builder of ANGELBERRIOS23/whatsapp-flow-studio (MIT, Copyright (c) 2026 Angel Berríos).
class Whatsapp::Flows::Exporter
  Spec = Whatsapp::Flows::Spec

  TEXT_COMPONENTS = { 'heading' => 'TextHeading', 'subheading' => 'TextSubheading', 'text' => 'TextBody', 'caption' => 'TextCaption' }.freeze
  CHOICE_COMPONENTS = { 'dropdown' => 'Dropdown', 'radio' => 'RadioButtonsGroup', 'checkbox' => 'CheckboxGroup' }.freeze
  MAX_FILE_KB = 25_600

  def initialize(definition)
    @definition = Spec.string_keys(definition)
    @screens = Array(@definition['screens'])
    @fields = Spec.fields(@definition)
  end

  def call
    { 'version' => Spec::FLOW_JSON_VERSION, 'screens' => @screens.each_index.map { |index| screen(index) } }
  end

  private

  def screen(index)
    json = {
      'id' => Spec.screen_id(index), 'title' => @screens[index]['title'].to_s.strip, 'data' => data_declarations(index),
      'layout' => { 'type' => 'SingleColumnLayout', 'children' => [form(index)] }
    }
    json.update('terminal' => true, 'success' => true) if last?(index)
    json
  end

  def last?(index)
    index == @screens.size - 1
  end

  def form(index)
    children = Array(@screens[index]['blocks']).map { |block| component(block, index) }
    { 'type' => 'Form', 'name' => 'form', 'children' => children + [footer(index)] }
  end

  def footer(index)
    action = if last?(index)
               { 'name' => 'complete', 'payload' => payload(index) }
             else
               { 'name' => 'navigate', 'next' => { 'type' => 'screen', 'name' => Spec.screen_id(index + 1) }, 'payload' => payload(index) }
             end
    { 'type' => 'Footer', 'label' => @screens[index]['button'].to_s.strip, 'on-click-action' => action }
  end

  # Everything collected up to and including this screen: this screen's answers from the form, the earlier ones from data.
  def payload(index)
    @fields.select { |field| field[:screen] <= index }.to_h do |field|
      source = field[:screen] == index ? 'form' : 'data'
      [field[:key], "${#{source}.#{field[:key]}}"]
    end
  end

  def data_declarations(index)
    @fields.select { |field| field[:screen] < index }.to_h { |field| [field[:key], declaration(field[:type])] }
  end

  def declaration(type)
    case type
    when 'optin' then { 'type' => 'boolean', '__example__' => false }
    when 'checkbox' then { 'type' => 'array', 'items' => { 'type' => 'string' }, '__example__' => [] }
    when 'photo', 'document' then file_declaration
    else { 'type' => 'string', '__example__' => '' }
    end
  end

  def file_declaration
    properties = %w[file_name mime_type sha256 id].index_with { { 'type' => 'string' } }
    { 'type' => 'array', 'items' => { 'type' => 'object', 'properties' => properties }, '__example__' => [] }
  end

  def component(block, screen_index)
    json = base_component(block)
    condition = block['visible_when']
    return json if condition.blank?

    { 'type' => 'If', 'condition' => expression(condition, screen_index), 'then' => [json] }
  end

  def base_component(block)
    type = block['type']
    return { 'type' => TEXT_COMPONENTS[type], 'text' => block['text'].to_s.strip } if TEXT_COMPONENTS.key?(type)
    return choice(block) if CHOICE_COMPONENTS.key?(type)
    return file(block) if Spec::FILE_BLOCKS.include?(type)

    simple_input(block)
  end

  def simple_input(block)
    json = { 'name' => block['key'], 'label' => block['label'].to_s.strip, 'required' => block['required'] == true }
    json['helper-text'] = block['helper'].to_s.strip if block['helper'].present? && %w[short_text long_text date].include?(block['type'])
    case block['type']
    when 'short_text' then json.merge('type' => 'TextInput', 'input-type' => block['input'].presence || 'text')
    when 'long_text' then json.merge('type' => 'TextArea')
    when 'date' then json.merge('type' => 'DatePicker')
    else json.merge('type' => 'OptIn')
    end
  end

  def choice(block)
    json = {
      'type' => CHOICE_COMPONENTS[block['type']], 'name' => block['key'], 'label' => block['label'].to_s.strip,
      'required' => block['required'] == true, 'data-source' => data_source(block)
    }
    json['helper-text'] = block['helper'].to_s.strip if block['helper'].present? && block['type'] == 'dropdown'
    json.update(selection_limits(block)) if block['type'] == 'checkbox'
    json
  end

  def data_source(block)
    Array(block['options']).map { |option| { 'id' => option['id'], 'title' => option['title'].to_s.strip } }
  end

  def selection_limits(block)
    { 'min-selected-items' => block['min'].to_i, 'max-selected-items' => block['max'].to_i }.select { |_name, value| value.positive? }
  end

  # A photo or document picker: the amounts count files, and a required one asks for at least one.
  def file(block)
    photo = block['type'] == 'photo'
    noun = photo ? 'photos' : 'documents'
    min = block['required'] == true ? [block['min_files'].to_i, 1].max : 0
    json = { 'type' => photo ? 'PhotoPicker' : 'DocumentPicker', 'name' => block['key'], 'label' => block['label'].to_s.strip,
             'max-file-size-kb' => MAX_FILE_KB, "min-uploaded-#{noun}" => min, "max-uploaded-#{noun}" => [block['max_files'].to_i, 1].max }
    json['description'] = block['helper'].to_s.strip if block['helper'].present?
    json.update(photo ? { 'photo-source' => 'camera_gallery' } : { 'allowed-mime-types' => Spec::DEFAULT_MIME_TYPES })
  end

  # One condition on one earlier answer: the answer of this screen is read from the form, an earlier one from the data.
  def expression(condition, screen_index)
    field = @fields.find { |item| item[:key] == condition['key'].to_s }
    source = field && field[:screen] == screen_index ? 'form' : 'data'
    operator = condition['op'] == 'not_equals' ? '!=' : '=='
    value = field && field[:type] == 'optin' ? condition['value'].to_s : "'#{condition['value']}'"
    "${#{source}.#{condition['key']}} #{operator} #{value}"
  end
end
