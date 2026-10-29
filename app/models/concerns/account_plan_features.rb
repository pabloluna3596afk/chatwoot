module AccountPlanFeatures
  extend ActiveSupport::Concern

  included do
    after_create_commit :sync_plan_features_after_create
    after_update_commit :sync_plan_features_after_update, if: :saved_change_to_plan_id?
  end

  def feature_source(flag)
    flag = flag.to_s
    return :system if Plans::AccountFeatureSync::SYSTEM_FLAGS.include?(flag)

    feature = Plan::FEATURES_BY_FLAG[flag]
    feature_key = feature ? feature[:key] : flag
    override = feature_override_for(feature_key)
    return override.enabled? ? :override_on : :override_off if override
    return :base if Plans::AccountFeatureSync::BASE_FLAGS.include?(flag)
    return :system unless feature

    :plan
  end

  def feature_override_for(feature_key)
    current_feature_overrides[feature_key]
  end

  def reset_feature_override_cache!
    @current_feature_overrides = nil
  end

  private

  def sync_plan_features_after_create
    sync_plan_features
  end

  def sync_plan_features_after_update
    sync_plan_features
  end

  def sync_plan_features
    Plans::AccountFeatureSync.call(self) if plan_id.present?
  end

  def current_feature_overrides
    @current_feature_overrides ||= account_feature_overrides.current.index_by(&:feature_key)
  end
end
