# Allowlist serializer for the unauthenticated plans endpoint consumed by the
# marketing website. Every exposed field is listed explicitly so that a column
# added to `plans` later (internal costs, payment keys, ids) never leaks. The
# three add-on prices below are public catalog data by design.
class Plans::PublicSerializer
  CURRENCY = 'USD'.freeze
  FEATURE_LABELS = JSON.parse(
    Rails.root.join('app/javascript/dashboard/i18n/locale/es/planCatalog.json').read
  ).fetch('PLAN_CATALOG').fetch('FEATURES').merge(
    # Captain is the name inside the CRM; the public site says "agente de IA".
    'captain_integration' => 'Agente de IA'
  ).freeze

  def self.payload(plans = Plan.catalog)
    plans = plans.to_a
    {
      currency: CURRENCY,
      updated_at: plans.map(&:updated_at).max&.utc&.iso8601(6),
      plans: plans.map { |plan| new(plan).as_json },
      extras: {
        packs: ExtraPack.catalog.map do |pack|
          { id: pack.id, bucket: pack.bucket, units: pack.units, price_usd: pack.price_usd.to_f,
            display_order: pack.display_order, validity_days: AccountExtraBalance::VALIDITY.in_days.to_i }
        end,
        monthly: plans.to_h { |plan| [plan.slug, new(plan).monthly_extras] }
      }
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
      recommended: @plan.is_recommended?,
      price_monthly: @plan.price_monthly.to_f,
      price_yearly: @plan.price_yearly.to_f,
      addon_agent_price: public_price(@plan.addon_agent_price),
      addon_bot_price: public_price(@plan.addon_bot_price),
      # Deprecated: retained for existing website clients. Use extras.packs instead.
      credit_unit_price: public_price(@plan.credit_unit_price),
      addon_inbox_price: public_price(@plan.addon_inbox_price),
      addon_storage_100mb_price: public_price(@plan.addon_storage_100mb_price),
      addon_storage_250mb_price: public_price(@plan.addon_storage_250mb_price),
      trial_days: @plan.limit(:trial_days),
      limits: limits,
      feature_keys: Array(@plan.feature_keys),
      base_feature_keys: base_feature_keys,
      features: feature_labels(Array(@plan.feature_keys)),
      base_features: feature_labels(base_feature_keys)
    }
  end

  def monthly_extras
    {
      agent: @plan.addon_agent_price.to_f, bot: @plan.addon_bot_price.to_f,
      inbox: @plan.addon_inbox_price.to_f, storage_100mb: @plan.addon_storage_100mb_price.to_f,
      storage_250mb: @plan.addon_storage_250mb_price.to_f
    }
  end

  private

  def public_price(value)
    value.to_f if value.positive?
  end

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
