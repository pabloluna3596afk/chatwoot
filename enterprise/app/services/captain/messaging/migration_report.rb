class Captain::Messaging::MigrationReport
  REPORT_STATES = {
    'available' => 'available',
    'new' => 'new',
    'marketing_off' => 'marketing_off',
    'needs_review' => 'needs_review/unsupported',
    'unsupported' => 'needs_review/unsupported',
    'changed' => 'needs_review/unsupported',
    'unavailable' => 'needs_review/unsupported',
    'disabled' => 'needs_review/unsupported',
    'excluded' => 'needs_review/unsupported',
    'authentication' => 'authentication',
    'needs_data' => 'needs_data',
    'pending' => 'pending/rejected',
    'rejected' => 'pending/rejected',
    'not_published_here' => 'not_published_here'
  }.freeze

  def initialize(assistant)
    @assistant = assistant
  end

  def perform
    fingerprint = Captain::Messaging::MigrationFingerprint.for(@assistant)
    report = { 'fingerprint' => fingerprint,
               'backup' => @assistant.config['messaging'].deep_dup, 'generated_at' => Time.current.utc.iso8601,
               'inboxes' => inbox_reports }
    unless fingerprint == Captain::Messaging::MigrationFingerprint.for(@assistant)
      raise Captain::Messaging::Migration::StaleReport, 'el reporte está desactualizado: genera uno nuevo'
    end

    report
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
    auto_preview = auto_availability(entry, inbox)
    { 'inbox_id' => inbox.id, 'before' => before_snapshot(entry),
      'after_preview' => after_preview(entry, availability, inbox), 'summary' => summary(entry, inbox, availability, auto_preview) }
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

  def summary(entry, inbox, before, after_auto)
    today = legacy_usable_names(entry, inbox, before)
    auto = usable_names(after_auto)
    {
      'inbox_name' => inbox.name,
      'before' => listed_resources(entry, inbox),
      'after_auto_would_allow' => state_names(after_auto),
      'differences' => { 'gained' => auto - today, 'lost' => today - auto }
    }
  end

  def listed_resources(entry, inbox)
    { 'templates' => listed_templates(entry, inbox), 'flows' => listed_flows(entry) }
  end

  def listed_templates(entry, inbox)
    Array(entry['templates']).map do |listed|
      current = current_template(inbox, listed)
      { 'name' => template_name(listed), 'category' => current&.fetch('category', nil),
        'purpose_present' => listed['purpose'].present?, 'params_present' => listed['processed_params'].present? }
    end
  end

  def current_template(inbox, listed)
    Array(inbox.channel.message_templates).find do |template|
      template['name'] == listed['name'] && template['language'].to_s.casecmp?(listed['language'].to_s)
    end
  end

  def listed_flows(entry)
    Array(entry['flows']).map do |listed|
      flow = @assistant.account.whatsapp_flows.find_by(id: listed['flow_id'])
      { 'name' => flow&.name || "Flow ##{listed['flow_id']}", 'category' => 'FLOW',
        'purpose_present' => listed['purpose'].present?, 'params_present' => false }
    end
  end

  def auto_availability(entry, inbox)
    preview_assistant = @assistant.dup
    preview_assistant.config = @assistant.config.deep_dup.merge('messaging' => preview_messaging(entry, inbox))
    Captain::Messaging::Availability.new(preview_assistant, inbox)
  end

  def preview_messaging(entry, inbox)
    converted = entry.deep_dup
    Captain::Messaging::LegacyEntryConverter.new(@assistant, converted).perform unless @assistant.messaging.mode(inbox.id) == 'auto'
    messaging = @assistant.config.fetch('messaging').deep_dup
    messaging['version'] = 2
    messaging['revision'] = messaging['revision'].to_i + 1
    messaging['inboxes'] = Array(messaging['inboxes']).map do |candidate|
      candidate.is_a?(Hash) && candidate['inbox_id'] == inbox.id ? converted : candidate
    end
    messaging
  end

  def state_names(availability)
    names = Hash.new { |hash, key| hash[key] = [] }
    (availability.templates + availability.flows).each do |item|
      bucket = REPORT_STATES.fetch(item.state, 'needs_review/unsupported')
      names[bucket] << resource_name(item)
    end
    names.transform_values(&:uniq)
  end

  # What the legacy list could send before the update: marketing templates a client had listed count as
  # "today" even though Captain no longer sends them, so the report shows what would be switched off.
  def legacy_usable_names(entry, inbox, availability)
    flows = availability.flows.select(&:available?).map { |item| resource_name(item) }
    templates = Array(entry['templates']).filter_map do |listed|
      current = current_template(inbox, listed)
      next unless current && current['status'].to_s.upcase == 'APPROVED' && @assistant.allow_paid_templates?

      template_name(listed)
    end
    (flows + templates).uniq
  end

  def usable_names(availability)
    (availability.templates + availability.flows)
      .select { |item| item.available? && (item.resource['language'].blank? || @assistant.allow_paid_templates?) }
      .map { |item| resource_name(item) }.uniq
  end

  def resource_name(item)
    return "Flow ##{item.resource['id']}" if item.resource['name'].blank?

    language = item.resource['language']
    language.present? ? "#{item.resource['name']} (#{language})" : item.resource['name']
  end

  def template_name(template)
    language = template['language']
    language.present? ? "#{template['name']} (#{language})" : template['name']
  end

  def approved_templates(inbox)
    Array(inbox.channel.message_templates)
      .select { |template| template['status'].to_s.upcase == 'APPROVED' }
      .group_by { |template| template['category'].to_s.downcase }
  end
end
