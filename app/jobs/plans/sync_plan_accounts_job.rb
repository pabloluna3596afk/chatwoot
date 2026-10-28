class Plans::SyncPlanAccountsJob < ApplicationJob
  queue_as :low

  def perform(plan_id)
    plan = Plan.find(plan_id)
    if plan.feature_keys.blank?
      Rails.logger.warn("Plan account sync skipped plan=#{plan.id} slug=#{plan.slug}: plan has no features")
      return
    end

    plan.accounts.find_each { |account| Plans::AccountFeatureSync.call(account) }
  end
end
