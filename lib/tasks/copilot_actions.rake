namespace :copilot do
  desc 'Read Copilot action audit events for an account (requires an account administrator id)'
  task actions_report: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    admin = account.account_users.find_by!(user_id: ENV.fetch('ADMIN_USER_ID'))
    raise 'ADMIN_USER_ID must be an account administrator' unless admin.administrator?

    CopilotActionEvent.includes(:item).where(account: account).order(:created_at).find_each do |event|
      puts [event.created_at.iso8601, event.item_id, event.event, event.user_id,
            event.payload_snapshot.to_json, event.metadata.to_json].join("\t")
    end
  end
end
