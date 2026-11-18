class EnqueueCaptainMessagingMigrationReport < ActiveRecord::Migration[7.2]
  def up
    add_column :captain_assistants, :config_migration_report, :jsonb, default: {}, null: false
    Migration::CaptainMessagingMigrationReportJob.perform_later if ChatwootApp.enterprise?
  end

  def down
    remove_column :captain_assistants, :config_migration_report
  end
end
