class Whatsapp::TemplateEditValidator
  VARIABLE = /\{\{\s*([^{}\s]+)\s*\}\}/
  EDITABLE_TYPES = %w[HEADER BODY FOOTER BUTTONS QUICK_REPLY URL PHONE_NUMBER COPY_CODE].freeze

  def initialize(original)
    @original = original.with_indifferent_access
  end

  def validate!(components, category: nil, **identity)
    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'edit_identity_locked' if identity.any? { |key, value| value != @original[key] }

    validate_status!(category)
    return if signature(components) == signature(@original.fetch(:components))

    raise Whatsapp::TemplateComponentsBuilder::Invalid, 'edit_structure_locked'
  end

  private

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
