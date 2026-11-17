class Captain::Capabilities::AllowedTemplates < Captain::Capabilities::Base
  def self.inboxes_for(assistant)
    whatsapp_inboxes_for(assistant)
  end

  def self.count_for(assistant)
    Array(assistant.config.dig('messaging', 'inboxes')).sum do |entry|
      next 0 unless entry.is_a?(Hash) && entry['enabled'] == true

      Array(entry['templates']).length
    end
  end

  def call
    return result('not_connected', 'not_connected_whatsapp') if whatsapp_inboxes.empty?

    entry = configured_entry
    return result('needs_setup', 'no_items') if entry.nil? || Array(entry['templates']).empty?
    return result('off', 'disabled') unless entry['enabled'] == true
    return result('off', 'templates_off') unless assistant.allow_paid_templates?

    result('ready')
  end
end
