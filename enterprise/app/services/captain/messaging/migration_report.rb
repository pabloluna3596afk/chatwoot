class Captain::Messaging::MigrationReport
  def initialize(assistant)
    @assistant = assistant
  end

  def perform
    { 'backup' => @assistant.config['messaging'].deep_dup, 'generated_at' => Time.current.utc.iso8601,
      'inboxes' => inbox_reports }
  end

  private

  def inbox_reports
    Array(@assistant.config.dig('messaging', 'inboxes')).filter_map do |entry|
      report_for(entry) if entry.is_a?(Hash)
    end
  end

  def report_for(entry)
    inbox = @assistant.account.inboxes.includes(:channel).find_by(id: entry['inbox_id'])
    return unless inbox

    availability = Captain::Messaging::Availability.new(@assistant, inbox)
    { 'inbox_id' => inbox.id, 'before' => before_snapshot(entry), 'after_preview' => after_preview(entry, availability, inbox) }
  end

  def before_snapshot(entry)
    entry.slice('mode', 'enabled', 'templates', 'flows').merge('mode' => entry.fetch('mode', 'list'))
  end

  def after_preview(entry, availability, inbox)
    {
      'templates' => approved_templates(inbox),
      'flows' => availability.eligible_flows.map { |flow| { 'id' => flow.id, 'name' => flow.name } },
      'mappings_changed' => [],
      'bindings_missing' => availability.templates.select { |item| item.state == 'needs_data' }.map(&:resource),
      'disabled' => entry['enabled'] != true,
      'activation_snapshot' => Captain::Messaging::Review.new(@assistant, inbox).activation_snapshot
    }
  end

  def approved_templates(inbox)
    Array(inbox.channel.message_templates)
      .select { |template| template['status'].to_s.upcase == 'APPROVED' }
      .group_by { |template| template['category'].to_s.downcase }
  end
end
