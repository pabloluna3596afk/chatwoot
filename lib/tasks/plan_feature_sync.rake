namespace :plans do # rubocop:disable Metrics/BlockLength
  desc 'Preview or apply plan feature synchronization (DRY_RUN=true by default)'
  task sync_account_features: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    Account.includes(:plan, :account_feature_overrides).find_each do |account|
      next unless account.plan

      before = Plans::AccountFeatureSync::SYNCED_FLAGS.index_with { |flag| account.feature_enabled?(flag) }
      desired = Plans::AccountFeatureSync::BASE_FLAGS.index_with { true }
      Plan::FEATURES.each do |feature|
        feature[:flags].each { |flag| desired[flag] = account.plan.feature_keys.include?(feature[:key]) }
      end
      account.account_feature_overrides.current.each do |override|
        Plan::ACCOUNT_FEATURES_BY_KEY.fetch(override.feature_key)[:flags].each { |flag| desired[flag] = override.enabled }
      end
      changes = desired.filter_map { |flag, value| [flag, [before[flag], value]] if before[flag] != value }.to_h
      puts "account=#{account.id} plan=#{account.plan.slug} changes=#{changes.inspect}"
      Plans::AccountFeatureSync.call(account) unless dry_run
    end
  end

  desc 'Fill plan feature keys from the approved ChatHub tier matrix (DRY_RUN=true by default)'
  task fill_feature_keys: :environment do
    basic = %w[captain_integration copilot calendar_integration integrations flows]
    start = basic + %w[campaigns automations macros api_and_webhooks]
    growth = start + %w[help_center]
    matrix = {
      'prueba' => %w[captain_integration],
      'gratis' => %w[captain_integration],
      'basico' => basic,
      'básico' => basic,
      'inicio' => start,
      'crecimiento' => growth,
      'negocio' => growth + %w[custom_roles sla help_center_semantic_search],
      'escala' => growth + %w[custom_roles sla help_center_semantic_search saml],
      'developer' => growth
    }
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    Plan.find_each do |plan|
      keys = matrix[plan.slug.downcase]
      next unless keys

      puts "plan=#{plan.slug} feature_keys=#{plan.feature_keys.inspect} -> #{keys.inspect}"
      plan.update!(feature_keys: keys) unless dry_run
    end
  end
end
