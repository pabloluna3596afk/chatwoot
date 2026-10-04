namespace :captain do
  namespace :appointments do
    desc 'Reconcile the appointments Captain booked for an account (dry run; APPLY=1 to write). Usage: rake captain:appointments:reconcile[ACCOUNT_ID]'
    task :reconcile, [:account_id] => :environment do |_task, args|
      abort 'Captain appointments are an Enterprise feature' unless ChatwootApp.enterprise?

      account = Account.find(args[:account_id] || abort('Usage: rake captain:appointments:reconcile[ACCOUNT_ID]'))
      apply = ENV['APPLY'].to_s == '1'
      result = Captain::AppointmentReconciler.new(account, apply: apply, log: ->(line) { puts line }).perform

      puts "Account #{account.id}: #{apply ? 'applied' : 'dry run, nothing written'}"
      result.to_h.each { |kind, ids| puts "  #{kind}: #{ids.size}#{ids.any? ? " (#{ids.join(', ')})" : ''}" }
    end
  end
end
