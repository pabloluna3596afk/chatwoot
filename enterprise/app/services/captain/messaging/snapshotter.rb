class Captain::Messaging::Snapshotter
  def self.perform!(assistant, inbox: nil)
    new(assistant, inbox: inbox).perform
  end

  def initialize(assistant, inbox: nil)
    @assistant = assistant
    @inbox = inbox
  end

  def perform
    messaging = @assistant.config['messaging']
    return unless messaging.is_a?(Hash)

    updated = messaging.deep_dup
    notices = snapshot_entries(updated['inboxes'])
    return if notices.empty?

    updated['revision'] = @assistant.messaging.revision + 1
    @assistant.update!(config: @assistant.config.merge('messaging' => updated))
    notices
  end

  private

  def snapshot_entries(entries)
    Array(entries).filter_map do |entry|
      next unless eligible_entry?(entry)

      inbox = @inbox || @assistant.account.inboxes.find_by(id: entry['inbox_id'])
      next unless inbox

      snapshot = Captain::Messaging::Review.new(@assistant, inbox).activation_snapshot
      entry['reviewed'] = snapshot
      activation_notice(inbox, snapshot)
    end
  end

  def eligible_entry?(entry)
    entry.is_a?(Hash) && entry.fetch('enabled', false) && entry.fetch('mode', 'list') == 'auto' &&
      !entry.key?('reviewed') && (!@inbox || entry['inbox_id'] == @inbox.id)
  end

  def activation_notice(inbox, snapshot)
    count = snapshot.values.sum(&:size)
    { inbox_id: inbox.id, count: count,
      message: I18n.t('captain.messaging.activated', locale: @assistant.account.locale, count: count, inbox: inbox.name) }
  end
end
