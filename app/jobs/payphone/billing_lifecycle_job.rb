class Payphone::BillingLifecycleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Payphone::BillingLifecycle.call
  end
end
