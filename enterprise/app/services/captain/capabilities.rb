class Captain::Capabilities
  REGISTRY_PATH = Rails.root.join('config/agents/capabilities.yml')

  def initialize(assistant)
    @assistant = assistant
  end

  def to_h
    groups = registry.fetch('groups').sort_by { |group| group.fetch('position') }
    capabilities = registry.fetch('capabilities').group_by { |capability| capability.fetch('group') }

    { groups: groups.map { |group| serialize_group(group, capabilities.fetch(group.fetch('id'), [])) } }
  end

  private

  attr_reader :assistant

  def registry
    @registry ||= YAML.load_file(REGISTRY_PATH).deep_stringify_keys
  end

  def serialize_group(group, capabilities)
    result = {
      id: group.fetch('id'),
      connection: connection_for(group.fetch('id')),
      items: capabilities.sort_by { |capability| capability.fetch('position') }.filter_map do |capability|
        serialize_capability(capability)
      end
    }
    result[:connect_route] = group['connect_route'] if group['connect_route']
    result
  end

  def connection_for(group_id)
    case group_id
    when 'whatsapp'
      inboxes = Captain::Capabilities::Base.whatsapp_inboxes_for(assistant)
      return 'not_connected' if inboxes.empty?
      return 'needs_review' if inboxes.any? { |inbox| inbox.channel.reauthorization_required? }

      'connected'
    when 'calendar'
      assistant.account.calendar_connections.active.exists? ? 'connected' : 'not_connected'
    else
      'always'
    end
  end

  def serialize_capability(capability)
    status_class = capability.fetch('status').constantize
    inboxes = inboxes_for(capability, status_class)
    results = results_for(capability, status_class, inboxes)
    status, reason = aggregate(results)
    count = status_class.count_for(assistant) if capability['count'] && status_class.respond_to?(:count_for)

    inbox_details = serialize_inboxes(inboxes, results) if capability.fetch('scope') == 'inbox'
    build_item(capability, status, reason, count, inbox_details || [])
  rescue StandardError => e
    Rails.logger.error("Captain capability #{capability['id']} failed for assistant #{assistant.id}: #{e.class}: #{e.message}")
    nil
  end

  def inboxes_for(capability, status_class)
    return [] unless capability.fetch('scope') == 'inbox'

    status_class.inboxes_for(assistant)
  end

  def results_for(capability, status_class, inboxes)
    return [status_class.new(assistant).call] if capability.fetch('scope') == 'assistant' || inboxes.empty?

    inboxes.map { |inbox| status_class.new(assistant, inbox).call }
  end

  def build_item(capability, status, reason, count, inbox_details)
    item = {
      id: capability.fetch('id'), kind: capability.fetch('kind'), status: status, reason: reason,
      count: count, configure_route: capability.fetch('configure_route'),
      inboxes: inbox_details
    }
    item[:configure_anchor] = capability['configure_anchor'] if capability['configure_anchor']
    item
  end

  def aggregate(results)
    ready = results.select { |result| result[:status] == 'ready' }
    return aggregate_ready(ready) if ready.any?

    aggregate_not_ready(results)
  end

  def aggregate_ready(results)
    reason = results.all? { |result| result[:reason] == 'window_only' } ? 'window_only' : nil
    ['ready', reason]
  end

  def aggregate_not_ready(results)
    status = %w[not_connected needs_setup off].find { |candidate| results.any? { |result| result[:status] == candidate } }
    first = results.find { |result| result[:status] == status }
    [status, first&.fetch(:reason)]
  end

  def serialize_inboxes(inboxes, results)
    return [] if inboxes.empty?

    inboxes.zip(results).map do |inbox, result|
      { inbox_id: inbox.id, inbox_name: inbox.name, status: result[:status], reason: result[:reason] }
    end
  end
end
