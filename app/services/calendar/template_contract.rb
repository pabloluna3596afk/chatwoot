# The binding contract is stricter than the legacy name lookup. Editing copy is allowed,
# but all values must come from the selected appointment and every action must be known.
class Calendar::TemplateContract
  COMPONENT_TYPES = %w[BODY HEADER FOOTER BUTTONS].freeze
  VARIABLE_COMPONENT_TYPES = %w[BODY BUTTONS].freeze

  def initialize(function:, language:, template:)
    @function = function.to_s
    @language = language
    @template = template
  end

  def incompatibility
    metadata_incompatibility || component_incompatibility
  end

  def snapshot
    {
      'version' => self.class.version(@template),
      'variables' => variables, 'actions' => actions
    }
  end

  # Use the existing structural comparison so JSONB key order and omitted examples
  # do not turn an unchanged remote version into an incompatible replacement.
  def self.version(template)
    identity = template.slice('id', 'name', 'language', 'category', 'parameter_format')
    identity['components'] = Whatsapp::TemplateSubmissionMatcher.comparable_components(template.fetch('components', []))
    Digest::SHA256.hexdigest(identity.to_json)
  end

  private

  def metadata_incompatibility
    return 'missing_template' unless @template
    return 'category' unless @template['category'].to_s.casecmp?('UTILITY')
    return 'status' unless @template['status'].to_s.casecmp?('APPROVED')
    return 'language' unless @template['language'] == @language
    return 'remote_identity' if @template['id'].blank?
    return 'parameter_format' unless @template['parameter_format'] == 'NAMED'
  end

  def component_incompatibility
    return 'components' unless valid_components?
    return 'variables' unless variables.sort == Calendar::TemplateDefinitions::VARIABLES.sort
    return 'buttons' unless valid_buttons?
  end

  def components
    Array(@template['components'])
  end

  def valid_components?
    valid_component_types? && components.all? { |component| static_component?(component) }
  end

  def valid_component_types?
    types = components.pluck('type')
    types.count('BODY') == 1 && types.uniq == types && (types - COMPONENT_TYPES).empty?
  end

  def static_component?(component)
    return true if VARIABLE_COMPONENT_TYPES.include?(component['type'])

    (component['type'] != 'HEADER' || component['format'] == 'TEXT') && component['text'].to_s.exclude?('{{')
  end

  def variables
    body = components.find { |component| component['type'] == 'BODY' }
    body.to_h['text'].to_s.scan(/{{\s*([^{}]+?)\s*}}/).flatten.uniq
  end

  def buttons
    components.find { |component| component['type'] == 'BUTTONS' }.to_h.fetch('buttons', [])
  end

  def valid_buttons?
    expected = Calendar::TemplateDefinitions.definition(@function, @language).fetch(:buttons)
    buttons.all? { |button| button['type'] == 'QUICK_REPLY' } && buttons.pluck('text') == expected
  end

  def actions
    buttons.pluck('text').zip(Calendar::TemplateDefinitions::ACTIONS).to_h
  end
end
