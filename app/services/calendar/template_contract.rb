# The binding contract is stricter than the legacy name lookup. Editing copy is allowed,
# but all values must come from the selected appointment and every action must be known.
class Calendar::TemplateContract
  def initialize(function:, language:, template:)
    @function = function.to_s
    @language = language
    @template = template
  end

  def incompatibility
    return 'missing_template' unless @template
    return 'category' unless @template['category'].to_s.casecmp?('UTILITY')
    return 'status' unless @template['status'].to_s.casecmp?('APPROVED')
    return 'language' unless @template['language'] == @language
    return 'remote_identity' if @template['id'].blank?
    return 'parameter_format' unless @template['parameter_format'] == 'NAMED'
    return 'components' unless valid_components?
    return 'variables' unless variables.sort == Calendar::TemplateDefinitions::VARIABLES.sort
    return 'buttons' unless valid_buttons?

    nil
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

  def components
    Array(@template['components'])
  end

  def valid_components?
    types = components.map { |component| component['type'] }
    return false unless types.count('BODY') == 1 && types.uniq == types && (types - %w[BODY HEADER FOOTER BUTTONS]).empty?

    components.all? do |component|
      next true if %w[BODY BUTTONS].include?(component['type'])

      (component['type'] != 'HEADER' || component['format'] == 'TEXT') && !component['text'].to_s.include?('{{')
    end
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
    buttons.all? { |button| button['type'] == 'QUICK_REPLY' } && buttons.map { |button| button['text'] } == expected
  end

  def actions
    buttons.map { |button| button['text'] }.zip(Calendar::TemplateDefinitions::ACTIONS).to_h
  end
end
