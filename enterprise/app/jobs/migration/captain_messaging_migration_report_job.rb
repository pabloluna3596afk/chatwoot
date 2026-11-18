class Migration::CaptainMessagingMigrationReportJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    Captain::Assistant.where("config ? 'messaging'").find_each do |assistant|
      assistant.with_lock do
        next if assistant.config_migration_report.key?('backup')

        assistant.update!(config_migration_report: Captain::Messaging::MigrationReport.new(assistant).perform)
      end
    end
  end
end
