class Captain::UsageLimitWarningJob < ApplicationJob
  queue_as :mailers

  def perform(account_plan_usage, bucket, percent, consumed, limit)
    AdministratorNotifications::AccountNotificationMailer
      .with(account: account_plan_usage.account)
      .usage_limit_warning(bucket, percent, consumed, limit)
      .deliver_now
  end
end
