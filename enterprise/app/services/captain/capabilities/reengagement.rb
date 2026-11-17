class Captain::Capabilities::Reengagement < Captain::Capabilities::Base
  def self.inboxes_for(assistant)
    whatsapp_inboxes_for(assistant)
  end

  def call
    return result('not_connected', 'not_connected_whatsapp') if whatsapp_inboxes.empty?
    return result('off', 'disabled') unless assistant.followup.reengagement_enabled?
    return result('off', 'templates_off') unless assistant.allow_paid_templates?
    return result('needs_setup', 'no_template') if assistant.followup.reengagement_template.blank?
    return result('needs_setup', 'template_unavailable') if Captain::TemplateMessage.approved(inbox, assistant.followup.reengagement_template).blank?

    result('ready')
  end
end
