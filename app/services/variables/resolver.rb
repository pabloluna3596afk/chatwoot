class Variables::Resolver
  def initialize(drops:)
    @drops = drops
  end

  # The legacy send path deliberately retains Liquid's permissive render mode.
  def render(text, protect_code: false)
    Liquid::Template.parse(protect_code ? self.class.protect_code(text) : text).render(@drops)
  end

  def preview(text, protect_code: false)
    source = protect_code ? self.class.protect_code(text) : text
    template = Liquid::Template.parse(source, error_mode: :strict)
    value = template.render(@drops)
    template.render(@drops, strict_variables: true, strict_filters: true)
    errors = template.errors
    status = preview_status(value, errors, template)
    { status: status, value: status == 'invalid' ? nil : value, errors: errors.map { |error| error.class.name }.uniq }
  rescue Liquid::Error => e
    { status: 'invalid', value: nil, errors: [e.class.name] }
  end

  def self.protect_code(text)
    text.gsub(/`(.*?)`/m, '{% raw %}`\\1`{% endraw %}')
  end

  private

  def preview_status(value, errors, template)
    return 'invalid' if errors.any? { |error| !error.is_a?(Liquid::UndefinedVariable) }
    return 'unavailable' if errors.any? && unavailable_context?(template)
    return 'missing' if errors.any? || value.empty?

    'value'
  end

  def unavailable_context?(template)
    roots = []
    Liquid::ParseTreeVisitor.for(template.root).add_callback_for(Liquid::VariableLookup) { |node| roots << node.name }.visit
    roots.any? { |root| Variables::Catalog::FIELDS.key?(root) && !@drops.key?(root) }
  end
end
