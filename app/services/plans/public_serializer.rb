# Allowlist serializer for the unauthenticated plans endpoint consumed by the
# marketing website. Every exposed field is listed explicitly so that a column
# added to `plans` later (costs, add-on prices, payment keys, ids) never leaks.
class Plans::PublicSerializer
  CURRENCY = 'USD'.freeze
  FEATURE_LABELS = JSON.parse(
    Rails.root.join('app/javascript/dashboard/i18n/locale/es/planCatalog.json').read
  ).fetch('PLAN_CATALOG').fetch('FEATURES').freeze

  def self.payload(plans = Plan.catalog)
    plans = plans.to_a
    {
      currency: CURRENCY,
      updated_at: plans.map(&:updated_at).max&.utc&.iso8601(3),
      plans: plans.map { |plan| new(plan).as_json }
    }
  end

  def initialize(plan)
    @plan = plan
  end

  def as_json
    {
      slug: @plan.slug,
      name: @plan.name,
      description: @plan.description,
      display_order: @plan.display_order,
      state: @plan.catalog_state,
      price_monthly: @plan.price_monthly.to_f,
      price_yearly: @plan.price_yearly.to_f,
      trial_days: @plan.limit(:trial_days),
      limits: limits,
      feature_keys: Array(@plan.feature_keys),
      base_feature_keys: base_feature_keys,
      features: feature_labels(Array(@plan.feature_keys)),
      base_features: feature_labels(base_feature_keys)
    }
  end

  private

  def base_feature_keys
    Plan::CATALOG_BASE_CAPABILITIES.pluck(:key)
  end

  def feature_labels(keys)
    keys.filter_map do |key|
      label = FEATURE_LABELS[key]
      { key: key, label: label } if label.present?
    end
  end

  def limits
    {
      monthly_responses: @plan.limit(:monthly_messages),
      assistants: @plan.limit(:max_captain_assistants),
      users: @plan.limit(:max_human_agents),
      inboxes: @plan.limit(:max_inboxes),
      storage_bytes: @plan.limit(:storage_mb)&.megabytes,
      emails_per_day: @plan.limit(:max_emails_per_day),
      trial_responses: @plan.limit(:trial_messages)
    }
  end
end
