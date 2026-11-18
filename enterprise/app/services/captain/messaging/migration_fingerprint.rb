require 'digest'

# All persisted inputs used by the migration preview, including variable bindings and WABA publications.
class Captain::Messaging::MigrationFingerprint
  def self.for(assistant)
    new(assistant).digest
  end

  def initialize(assistant)
    @assistant = assistant
  end

  def digest
    Digest::SHA256.hexdigest(canonical(config: @assistant.config, inboxes: inboxes, flows: flows).to_json)
  end

  private

  def inboxes
    ids = Array(@assistant.config.dig('messaging', 'inboxes')).map { |entry| entry.fetch('inbox_id') }
    @assistant.account.inboxes.where(id: ids).includes(:channel).order(:id).map do |inbox|
      channel = inbox.channel
      { inbox: inbox.attributes, channel: channel.attributes.slice('id', 'provider', 'provider_config', 'message_templates',
                                                                   'template_variable_bindings', 'phone_number_health') }
    end
  end

  def flows
    @assistant.account.whatsapp_flows.includes(:whatsapp_flow_publications).order(:id).map do |flow|
      { flow: flow.attributes, publications: flow.whatsapp_flow_publications.sort_by(&:id).map(&:attributes) }
    end
  end

  def canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
