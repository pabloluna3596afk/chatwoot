module Whatsapp::TemplateSubmissionMatcher
  def self.matches?(payload, remote)
    expected_format = payload.fetch('parameter_format', 'POSITIONAL')
    return false unless (remote['parameter_format'] || 'POSITIONAL') == expected_format

    expected = comparable_components(payload.fetch('components'))
    actual = comparable_components(remote.fetch('components', []))
    expected == actual
  end

  # Meta can omit text examples on GET. Media handles must match exactly: an unavailable handle is ambiguous.
  def self.comparable_components(components)
    components.map do |component|
      comparable = component.slice('type', 'format', 'text', 'buttons')
      comparable['buttons'] = component.fetch('buttons').map { |button| comparable_button(button) } if component['buttons']
      comparable['example'] = component['example'] if Whatsapp::TemplateComponentsBuilder::MEDIA_FORMATS.include?(component['format'])
      comparable
    end
  end

  def self.comparable_button(button)
    keys = %w[type text url phone_number]
    keys << 'example' if button['type'] == 'COPY_CODE'
    button.slice(*keys)
  end
end
