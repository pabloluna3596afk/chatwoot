namespace :plans do # rubocop:disable Metrics/BlockLength
  desc 'Preview or apply plan feature synchronization (DRY_RUN=true by default)'
  task sync_account_features: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    Account.includes(:plan, :account_feature_overrides).find_each do |account|
      next unless account.plan

      if account.plan.feature_keys.blank?
        puts "SALTADA: plan sin features account=#{account.id} plan=#{account.plan.slug}"
        next
      end

      changes = Plans::AccountFeatureSync.preview(account)
      puts "account=#{account.id} plan=#{account.plan.slug} changes=#{changes.inspect}"
      Plans::AccountFeatureSync.call(account) unless dry_run
    end
  end

  desc 'Fill plan feature keys from the approved ChatHub tier matrix (DRY_RUN=true by default)'
  task fill_feature_keys: :environment do
    basic = %w[captain_integration captain_tasks calendar_integration integrations flows]
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

  desc 'Migrate legacy copilot plan feature keys to captain_tasks (idempotent)'
  task migrate_copilot_feature_keys: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    Plan.where("feature_keys @> '[\"copilot\"]'::jsonb").find_each do |plan|
      keys = (plan.feature_keys - ['copilot'] + ['captain_tasks']).uniq
      puts "plan=#{plan.slug} feature_keys=#{plan.feature_keys.inspect} -> #{keys.inspect}"
      plan.update!(feature_keys: keys) unless dry_run
    end
  end

  desc 'Renumber plans display_order by monthly price (DRY_RUN=true by default)'
  task order_by_price: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    Plan.order(:price_monthly, :id).each_with_index do |plan, index|
      puts "plan=#{plan.slug} price=#{plan.price_monthly} display_order=#{plan.display_order} -> #{index}"
      plan.update_column(:display_order, index) unless dry_run || plan.display_order == index # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
