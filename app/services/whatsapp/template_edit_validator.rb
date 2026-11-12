class Whatsapp::TemplateEditValidator
  VARIABLE = /\{\{\s*([^{}\s]+)\s*\}\}/
  EDITABLE_TYPES = %w[HEADER BODY FOOTER BUTTONS QUICK_REPLY URL PHONE_NUMBER COPY_CODE].freeze

  def initialize(original)
    @original = original.with_indifferent_access
  end

  def validate!(components, category: nil, **identity)
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'edit_identity_locked' if identity.any? { |key, value| value != @original[key] }

    validate_status!(category) unless unchanged?(components, category: category)
    return if signature(components) == signature(@original.fetch(:components))

    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'edit_structure_locked'
  end

  # Keep text and array order intact; the form trims example values.
  def unchanged?(components, category: nil)
    (category.blank? || category == @original[:category]) &&
      normalized(components) == normalized(@original.fetch(:components))
  end

  private

  def normalized(value, example: false)
    case value
    when Hash then normalized_hash(value, example: example)
    when Array then value.map { |item| normalized(item, example: example) }
    when String then example ? value.strip : value
    else value
    end
  end

  def normalized_hash(value, example:)
    value.to_h.each_with_object({}) do |(key, item), result|
      result[key.to_s] = normalized(item, example: example || key.to_s == 'example')
    end
  end

  def validate_status!(category)
    if category.present? && @original[:status] == 'APPROVED' && category != @original[:category]
      raise Whatsapp::TemplateComponentsBuilder::Invalid, 'category_locked'
    end
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'edit_status_locked' unless %w[APPROVED REJECTED PAUSED].include?(@original[:status])
  end

  def signature(components)
    components.map do |component|
      item = component.to_h.with_indifferent_access
      next item unless EDITABLE_TYPES.include?(item[:type])

      { type: item[:type], format: item[:format], text: item[:text].to_s.scan(VARIABLE).flatten,
        url: item[:url].to_s.scan(VARIABLE).flatten, buttons: item[:buttons] && signature(item[:buttons]) }
    end
  end
end
