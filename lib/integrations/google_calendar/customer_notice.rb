# The notice a customer gets when an appointment is booked or cancelled from their WhatsApp conversation: an approved
# template of the activation kit (Calendar::ActivationKit), sent as a template message so it also reaches the customer
# outside the 24-hour window. The values are already resolved here (the message surface of the variables catalog does not
# know appointments) and the message is marked as resolved so nothing a contact typed is rendered as Liquid.
class Integrations::GoogleCalendar::CustomerNotice
  DATE_FORMATS = { 'es' => '%d/%m/%Y', 'en' => '%m/%d/%Y' }.freeze

  def initialize(conversation:, record:, timezone:, sender: nil, template_name: Calendar::ActivationKit::TEMPLATE_NAME)
    @template_name = template_name
    @conversation = conversation
    @sender = sender
    @record = record
    @timezone = timezone
  end

  def whatsapp_cloud?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  # The requested approved template of this channel, or nil while it is missing, pending or rejected.
  def template
    @template ||= Array(channel.message_templates).find do |item|
      item.is_a?(Hash) && item['name'] == @template_name && item['status'].to_s.casecmp?('approved') &&
        item['language'].to_s.casecmp?(language)
    end
  end

  def deliver!
    return false if template.blank?

    values = body_values
    message = @conversation.messages.new(
      account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing, sender: @sender,
      content: rendered_body(values),
      additional_attributes: { 'template_params' => template_params(values), 'calendar_event_id' => @record.id }
    )
    message.variables_resolved!
    message.save!
    true
  end

  private

  def channel
    @conversation.inbox.channel
  end

  def language
    @language ||= Calendar::ActivationKit.new(@conversation.account).language
  end

  def zone
    @zone ||= Time.find_zone!(@timezone)
  end

  def body_values
    start = @record.start_at.in_time_zone(zone)
    { 'nombre' => @conversation.contact&.name.to_s, 'cita' => @record.summary.to_s,
      'fecha' => start.strftime(DATE_FORMATS.fetch(language)), 'hora' => start.strftime('%H:%M') }
  end

  def body_text
    body = Array(template['components']).find { |component| component['type'] == 'BODY' }
    body&.dig('text').presence || Calendar::ActivationKit::DEFINITIONS.fetch(@template_name).fetch(language)[:body]
  end

  def rendered_body(values)
    body_text.gsub(/{{\s*([a-z0-9_]+)\s*}}/) { |placeholder| values.fetch(Regexp.last_match(1), placeholder) }
  end

  def template_params(values)
    { 'name' => template['name'], 'language' => template['language'], 'category' => template['category'],
      'namespace' => template['namespace'], 'content_mode' => 'rendered', 'processed_params' => { 'body' => values } }.compact
  end
end
