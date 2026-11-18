# What the owner allows Captain to send, read from assistant.config['messaging'] (see Captain::MessagingValidator):
# per WhatsApp inbox a switch and the Flows and templates it may send. Nothing is allowed unless an inbox entry says so
# with `enabled: true`; the model never widens it.
class Captain::MessagingSettings
  def initialize(raw)
    @raw = raw.is_a?(Hash) ? raw : {}
  end

  def version
    @raw['version']
  end

  def revision
    @raw['revision'].to_i
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

  def mode(inbox_id)
    entry_for(inbox_id)&.fetch('mode', 'list') || 'list'
  end

  def excluded?(inbox_id, kind, key)
    Array(entry_for(inbox_id)&.dig('excluded', kind)).include?(key)
  end

  def marketing_included?(inbox_id, key)
    Array(entry_for(inbox_id)&.dig('included_marketing')).include?(key)
  end

  def note_for(inbox_id, key)
    values = entry_for(inbox_id)&.fetch('notes', {}).to_h
    values.find { |saved_key, _value| Captain::Messaging::TemplateKey.normalize(saved_key) == Captain::Messaging::TemplateKey.normalize(key) }&.last
  end

  def params_for(inbox_id, key)
    values = entry_for(inbox_id)&.fetch('params', {}).to_h
    values.find { |saved_key, _value| Captain::Messaging::TemplateKey.normalize(saved_key) == Captain::Messaging::TemplateKey.normalize(key) }&.last
  end
end
