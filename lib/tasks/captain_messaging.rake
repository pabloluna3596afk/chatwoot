namespace :captain do
  namespace :messaging do
    desc 'Convert a reviewed assistant messaging configuration to auto mode'
    task :convert, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      Captain::Messaging::Migration.convert!(assistant)
    rescue Captain::Messaging::Migration::StaleReport => e
      abort e.message
    end

    desc 'Restore the exact messaging configuration saved by the migration report'
    task :restore, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      Captain::Messaging::Migration.restore!(assistant)
    end

    desc 'Print the stored before/after messaging migration report for an assistant'
    task :report, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      Migration::CaptainMessagingMigrationReportJob.perform_now(assistant.id)
      assistant.reload
      puts Captain::Messaging::MigrationReportText.new(assistant.config_migration_report).render
    end
  end
end
