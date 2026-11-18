class Migration::CaptainMessagingMigrationReportJob < ApplicationJob
  queue_as :async_database_migration

  def perform(assistant_id = nil)
    assistants = Captain::Assistant.where("config ? 'messaging'")
    assistants = assistants.where(id: assistant_id) if assistant_id
    assistants.find_each do |assistant|
      assistant.with_lock do
        stored_report = assistant.config_migration_report
        next if stored_report['backup'].present? && Array(stored_report['inboxes']).all? { |inbox| inbox.key?('summary') }

        report = Captain::Messaging::MigrationReport.new(assistant).perform
        report['backup'] = stored_report['backup'] if stored_report['backup'].present?
        assistant.update!(config_migration_report: report)
      end
    end
  end
end
