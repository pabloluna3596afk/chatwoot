namespace :captain do
  namespace :messaging do
    desc 'Convert a reviewed assistant messaging configuration to auto mode'
    task :convert, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      Captain::Messaging::Migration.convert!(assistant)
    end

    desc 'Restore the exact messaging configuration saved by the migration report'
    task :restore, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      Captain::Messaging::Migration.restore!(assistant)
    end
  end
end
