class Plans::ExpireAccountFeatureOverridesJob < ApplicationJob
  queue_as :low

  def perform
    AccountFeatureOverride.where(expires_at: ...Time.current).find_each(&:destroy!)
  end
end
