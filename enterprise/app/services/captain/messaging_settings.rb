# What the owner allows Captain to send, read from assistant.config['messaging'] (see Captain::MessagingValidator):
# per WhatsApp inbox a switch and the Flows and templates it may send. Nothing is allowed unless an inbox entry says so
# with `enabled: true`; the model never widens it.
class Captain::MessagingSettings
  def initialize(raw)
    @raw = raw.is_a?(Hash) ? raw : {}
  end

  # The entry of an inbox that is switched on, or nil.
  def entry_for(inbox_id)
    Array(@raw['inboxes']).find { |entry| entry.is_a?(Hash) && entry['inbox_id'] == inbox_id && entry['enabled'] == true }
  end

  def flow(inbox_id, flow_id)
    Array(entry_for(inbox_id)&.dig('flows')).find { |flow| flow['flow_id'] == flow_id }
  end

  def template(inbox_id, name, language)
    Array(entry_for(inbox_id)&.dig('templates')).find do |template|
      template['name'] == name && template['language'].to_s.casecmp?(language.to_s)
    end
  end
end
