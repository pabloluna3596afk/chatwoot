# An approved WhatsApp template picked in an assistant's settings ({ 'name' =>, 'language' => }), turned into the
# message payload Chatwoot sends. Shared by every Captain message that, outside the 24 h window, has to be a template.
class Captain::TemplateMessage
  BODY_VARIABLE = /\{\{\s*([^}\s]+)\s*\}\}/

  # The approved entry of the inbox's WhatsApp templates, or nil (not found, or not approved).
  def self.approved(inbox, reference)
    return if reference.blank? || inbox.channel_type != 'Channel::Whatsapp'

    Array(inbox.channel.message_templates).find do |entry|
      entry['name'] == reference['name'] &&
        entry['language'].to_s.casecmp?(reference['language']) &&
        entry['status'].to_s.casecmp?('approved')
    end
  end

  # [template_params payload, text shown in the conversation]. `values` maps the body variable ("1", "2"...) to its
  # text; a variable with no value is sent as "-".
  def self.build(entry, values)
    body = Array(entry['components']).find { |component| component['type'].to_s.casecmp?('BODY') }
    text = body&.dig('text').to_s
    parameters = text.scan(BODY_VARIABLE).flatten.uniq.index_with { |key| values[key].presence || '-' }
    payload = { name: entry['name'], namespace: entry['namespace'], language: entry['language'], category: entry['category'],
                processed_params: { body: parameters } }
    [payload, text.gsub(BODY_VARIABLE) { parameters[Regexp.last_match(1)] || '-' }.presence || entry['name']]
  end
end
