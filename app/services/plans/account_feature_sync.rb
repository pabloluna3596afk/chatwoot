class Plans::AccountFeatureSync
  PLAN_FLAGS = Plan::PLAN_FLAGS
  SYSTEM_FLAGS = Featurable::FEATURE_LIST.filter_map do |feature|
    feature['name'] if PLAN_FLAGS.exclude?(feature['name']) &&
                       (feature['chatwoot_internal'] || feature['deprecated'] || feature['enabled'] != true ||
                        feature['premium'] == true || feature['name'] == 'chatwoot_v4')
  end.freeze
  BASE_FLAGS = Featurable::FEATURE_LIST.filter_map do |feature|
    name = feature['name']
    name if feature['enabled'] == true && SYSTEM_FLAGS.exclude?(name) && PLAN_FLAGS.exclude?(name)
  end.freeze
  SYNCED_FLAGS = (PLAN_FLAGS + BASE_FLAGS).uniq.freeze

  def self.call(account)
    new(account).call
  end

  def self.preview(account)
    new(account).preview
  end

  def initialize(account)
    @account = account
  end

  def call
    return if account.plan.blank?

    if account.plan.feature_keys.blank?
      Rails.logger.warn("Plan feature sync skipped account=#{account.id} plan=#{account.plan.slug}: plan has no features")
      return
    end

    changes = preview
    apply(changes)
    changes
  end

  def preview
    return {} if account.plan.blank? || account.plan.feature_keys.blank?

    desired_feature_flags.each_with_object({}) do |(flag, enabled), changed|
      current = account.feature_enabled?(flag)
      changed[flag] = [current, enabled] if current != enabled
    end
  end

  private

  attr_reader :account

  def apply(changes)
    changes.each do |flag, (_current, enabled)|
      account.public_send("feature_#{flag}=", enabled)
    end
    account.save! if changes.any?
    Rails.logger.info("Plan feature sync account=#{account.id} plan=#{account.plan.slug} changes=#{changes}")
  end

  def desired_feature_flags
    desired = BASE_FLAGS.index_with { true }
    Plan::FEATURES.each do |feature|
      enabled = account.plan.feature_keys.include?(feature[:key])
      feature[:flags].each { |flag| desired[flag] = enabled }
    end
    account.account_feature_overrides.current.each do |override|
      Plan::ACCOUNT_FEATURES_BY_KEY.fetch(override.feature_key)[:flags].each { |flag| desired[flag] = override.enabled }
    end
    desired
  end
end
