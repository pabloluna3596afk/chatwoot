module Captain
  class UsageLimitWarningJob < ApplicationJob
    queue_as :mailers

    def perform(account_plan_usage, percent)
      AdministratorNotifications::AccountNotificationMailer
        .with(account: account_plan_usage.account)
        .usage_limit_warning(percent, account_plan_usage.responses_consumed)
        .deliver_now
    end
  end
end