# Structural checks of a Flow JSON (Meta's format), run on what Whatsapp::Flows::Exporter produces and before anything is
# sent to Meta. Meta validates too (the upload answers with validation_errors); this catches the usual mistakes earlier.
#
#   result = Whatsapp::Flows::FlowJsonValidator.new(flow_json).call
#   result.errors    # [{ code: 'missing_payload_data', screen: 'PANTALLA_B', details: { keys: ['nombre'] } }]
#
# The rules are ported from gokapso/flowso (src/validator, MIT License, Copyright (c) 2026 Kapso) and from the gotchas
# of ANGELBERRIOS23/whatsapp-flow-studio (MIT License, Copyright (c) 2026 Angel Berríos), checked against Meta's error codes
# (https://developers.facebook.com/documentation/business-messaging/whatsapp/flows/reference/error-codes):
#
# The full text of both licenses is in NOTICE.md, next to this file.
class Whatsapp::Flows::FlowJsonValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end
  end

  SCREEN_ID_FORMAT = /\A[A-Za-z_]+\z/
  MAX_CHILDREN = 50
  FORM_REFERENCE = /\$\{form\.([A-Za-z0-9_]+)\}/
  DATA_REFERENCE = /\$\{data\.([A-Za-z0-9_]+)\}/

  def initialize(flow_json)
    @flow = flow_json.is_a?(Hash) ? flow_json.deep_stringify_keys : {}
    @errors = []
    @warnings = []
  end

  def call
    screens = @flow['screens']
    if screens.is_a?(Array) && screens.any?
      check_flow(screens)
    else
      add('no_screens')
    end
    Result.new(@errors, @warnings)
  end

  private

  def check_flow(screens)
    add('invalid_version') if @flow['version'].blank?
    check_ids(screens)
    screens.each { |screen| check_screen(screen, screens) }
    check_flow_ends(screens)
    check_reachability(screens)
  end

  def add(code, screen = nil, details = {})
    @errors << { code: code, screen: screen, details: details }
    nil
  end

  def check_ids(screens)
    ids = screens.pluck('id')
    ids.each do |id|
      add('screen_id_invalid', id) unless id.to_s.match?(SCREEN_ID_FORMAT)
      add('screen_id_reserved', id) if id.to_s.casecmp?('success')
    end
    ids.tally.each { |id, count| add('screen_id_duplicate', id) if count > 1 }
  end

  def check_screen(screen, screens)
    id = screen['id']
    components = flatten(screen.dig('layout', 'children'))
    add('too_many_components', id, limit: MAX_CHILDREN) if components.size > MAX_CHILDREN
    check_names(components, id)
    check_references(screen, components)
    check_footer(screen, components, screens)
  end

  # Every component of the screen, going into Forms, Ifs and Switches.
  def flatten(children)
    Array(children).flat_map do |child|
      next [] unless child.is_a?(Hash)

      nested = Array(child['children']) + Array(child['then']) + Array(child['else']) + Array(child['cases']&.values).flatten
      [child] + flatten(nested)
    end
  end

  def check_names(components, id)
    names = components.filter_map { |component| component['name'] if component['name'].present? && component['type'] != 'Form' }
    names.tally.each { |name, count| add('duplicate_field_name', id, name: name) if count > 1 }
  end

  def check_references(screen, components)
    texts = components.flat_map { |component| strings(component) }
    check_form_references(screen, components, texts)
    check_data_references(screen, texts)
  end

  def check_form_references(screen, components, texts)
    names = components.filter_map { |component| component['name'] if component['type'] != 'Form' }
    references(texts, FORM_REFERENCE).each do |name|
      add('unknown_form_reference', screen['id'], name: name) unless names.include?(name)
    end
  end

  def check_data_references(screen, texts)
    data = screen['data'] || {}
    references(texts, DATA_REFERENCE).each do |name|
      add('undeclared_data_reference', screen['id'], name: name) unless data.key?(name)
    end
    data.each do |name, schema|
      add('data_without_example', screen['id'], name: name) unless schema.is_a?(Hash) && schema.key?('__example__')
    end
  end

  def references(texts, pattern)
    texts.flat_map { |text| text.scan(pattern).flatten }.uniq
  end

  def strings(value)
    case value
    when String then [value]
    when Hash then value.except('children', 'then', 'else', 'cases').values.flat_map { |item| strings(item) }
    when Array then value.flat_map { |item| strings(item) }
    else []
    end
  end

  def check_footer(screen, components, screens)
    id = screen['id']
    footers = components.select { |component| component['type'] == 'Footer' }
    return add('footer_missing', id) if footers.empty?

    add('footer_multiple', id) if footers.size > 1
    action = footers.first['on-click-action'] || {}
    footer_label = footers.first['label'].to_s
    add('footer_emoji', id) if footer_label.match?(Whatsapp::Flows::Spec::EMOJI)
    check_action(screen, action, screens)
  end

  def check_action(screen, action, screens)
    id = screen['id']
    if screen['terminal']
      add('terminal_must_complete', id) unless action['name'] == 'complete'
    elsif action['name'] == 'navigate'
      check_navigate(screen, action, screens)
    else
      add('screen_must_navigate', id)
    end
  end

  def check_navigate(screen, action, screens)
    target = screens.find { |item| item['id'] == action.dig('next', 'name') }
    return add('navigate_unknown_screen', screen['id'], target: action.dig('next', 'name')) if target.nil?

    missing = (target['data'] || {}).keys - (action['payload'] || {}).keys
    add('missing_payload_data', screen['id'], target: target['id'], keys: missing) if missing.any?
  end

  def check_flow_ends(screens)
    terminals = screens.select { |screen| screen['terminal'] }
    return add('no_terminal_screen') if terminals.empty?

    add('no_success_screen') unless terminals.any? { |screen| screen['success'] }
  end

  # Every screen has to be reachable from the first one through navigate actions, and the path cannot loop back.
  def check_reachability(screens)
    edges = screens.to_h { |screen| [screen['id'], targets(screen)] }
    reached = walk(screens.first['id'], edges, [])
    (edges.keys - reached).each { |id| add('unreachable_screen', id) }
  end

  def targets(screen)
    flatten(screen.dig('layout', 'children')).filter_map do |component|
      action = component['on-click-action']
      action.dig('next', 'name') if action.is_a?(Hash) && action['name'] == 'navigate'
    end
  end

  def walk(id, edges, path)
    if path.include?(id)
      add('screens_loop', id)
      return []
    end

    ([id] + Array(edges[id]).flat_map { |target| walk(target, edges, path + [id]) }).uniq
  end
end
