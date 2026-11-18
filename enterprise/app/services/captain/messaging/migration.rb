class Captain::Messaging::Migration
  class StaleReport < StandardError; end

  def self.convert!(assistant)
    assistant.with_lock { convert_locked!(assistant) }
  end

  def self.restore!(assistant)
    assistant.with_lock do
      backup = assistant.config_migration_report['pre_conversion_config']
      raise ArgumentError, 'Messaging backup report is missing' unless backup.is_a?(Hash)

      assistant.update!(config: backup.deep_dup)
    end
  end

  def self.convert_locked!(assistant)
    raise ArgumentError, 'Messaging backup report is missing' unless assistant.config_migration_report['backup'].is_a?(Hash)
    return if converted?(assistant)

    converted = converted_messaging(assistant)
    report = assistant.config_migration_report.deep_dup
    unless report['fingerprint'] == Captain::Messaging::MigrationFingerprint.for(assistant)
      raise StaleReport, 'el reporte está desactualizado: genera uno nuevo'
    end

    report['pre_conversion_config'] = assistant.config.deep_dup
    assistant.update!(config: assistant.config.merge('messaging' => converted), config_migration_report: report)
  end

  def self.converted_messaging(assistant)
    converted = assistant.config['messaging'].deep_dup
    converted['version'] = 2
    converted['revision'] = converted['revision'].to_i + 1
    Array(converted['inboxes']).each do |entry|
      Captain::Messaging::LegacyEntryConverter.new(assistant, entry).perform if entry.is_a?(Hash)
    end
    converted
  end

  def self.converted?(assistant)
    messaging = assistant.config['messaging']
    messaging.is_a?(Hash) && messaging['version'] == 2 && Array(messaging['inboxes']).all? { |entry| entry['mode'] == 'auto' }
  end
  private_class_method :convert_locked!, :converted_messaging
end
