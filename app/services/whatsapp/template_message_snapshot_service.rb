# Store the approved visual definition once, after Message resolves its Liquid parameters.
class Whatsapp::TemplateMessageSnapshotService
  def initialize(message)
    @message = message
    @reference = message.additional_attributes.fetch('template_params')
  end

  def perform
    template = find_template
    return unless template

    @params = Whatsapp::TemplateParameterConverterService.new(@reference.deep_dup, template).normalize_to_enhanced['processed_params']
    snapshot(template)
  end

  private

  def find_template
    @message.inbox.channel.message_templates.find do |entry|
      entry['name'] == @reference['name'] && entry['language'].to_s.casecmp?(@reference['language'].to_s) &&
        entry['status'].to_s.casecmp?('approved')
    end
  end

  def snapshot(template)
    @template = template
    template.slice('name', 'language', 'category').merge(
      'header' => header_snapshot(component('HEADER')),
      'footer' => footer_snapshot,
      'buttons' => button_snapshots
    ).compact
  end

  def component(type)
    Array(@template['components']).find { |entry| entry['type'] == type }
  end

  def footer_snapshot
    footer = component('FOOTER')
    footer && render_text(footer['text'], @params['footer'])
  end

  def button_snapshots
    Array(component('BUTTONS')&.dig('buttons')).map { |button| button.slice('type', 'text') }
  end

  def header_snapshot(header)
    return unless header

    snapshot = header.slice('format')
    snapshot['text'] = render_text(header['text'], @params['header']) if header['format'] == 'TEXT'
    snapshot
  end

  def render_text(text, params)
    Whatsapp::TemplateContentRendererService.new(
      content: text.to_s, body_params: params || {}, value_renderer: ->(value) { value }, message_drops: {}
    ).perform
  end
end
