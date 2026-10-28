class Plans::SyncPlanAccountsJob < ApplicationJob
  queue_as :low

  def perform(plan_id)
    Plan.find(plan_id).accounts.find_each { |account| Plans::AccountFeatureSync.call(account) }
  end
end
