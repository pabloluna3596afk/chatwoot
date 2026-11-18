class Captain::Messaging::Migration
  def self.convert!(assistant)
    assistant.with_lock { convert_locked!(assistant) }
  end

  def self.restore!(assistant)
    assistant.with_lock do
      backup = assistant.config_migration_report['backup']
      raise ArgumentError, 'Messaging backup report is missing' unless backup.is_a?(Hash)

      assistant.update!(config: assistant.config.merge('messaging' => backup.deep_dup))
    end
  end

  def self.convert_locked!(assistant)
    raise ArgumentError, 'Messaging backup report is missing' unless assistant.config_migration_report['backup'].is_a?(Hash)
    return if already_converted?(assistant.config['messaging'])

    converted = assistant.config['messaging'].deep_dup
    converted['version'] = 2
    converted['revision'] = converted['revision'].to_i + 1
    Array(converted['inboxes']).each do |entry|
      Captain::Messaging::LegacyEntryConverter.new(assistant, entry).perform if entry.is_a?(Hash)
    end
    assistant.update!(config: assistant.config.merge('messaging' => converted))
  end

  def self.already_converted?(messaging)
    messaging.is_a?(Hash) && messaging['version'] == 2 && Array(messaging['inboxes']).all? { |entry| entry['mode'] == 'auto' }
  end
  private_class_method :convert_locked!, :already_converted!
end
