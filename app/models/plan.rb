# == Schema Information
#
# Table name: plans
#
#  id                 :bigint           not null, primary key
#  addon_agent_price  :decimal(10, 2)   default(0.0), not null
#  addon_bot_price    :decimal(10, 2)   default(0.0), not null
#  captain_daily_tests :integer        default(0), not null
#  coming_soon        :boolean          default(FALSE), not null
#  credit_unit_price  :decimal(10, 4)   default(0.0), not null
#  description        :string
#  display_order      :integer          default(0), not null
#  feature_keys       :jsonb            default([]), not null
#  limits             :jsonb            default({}), not null
#  is_active          :boolean          default(TRUE), not null
#  is_default_trial   :boolean          default(FALSE), not null
#  is_public          :boolean          default(TRUE), not null
#  max_captain_assistants :integer      default(1), not null
#  max_documents      :integer          default(10), not null
#  max_emails_per_day :integer          default(0), not null
#  max_human_agents   :integer          default(3), not null
#  max_inboxes        :integer          default(1), not null
#  monthly_messages   :integer          default(0), not null
#  name               :string           not null
#  price_monthly      :decimal(10, 2)   default(0.0), not null
#  price_yearly       :decimal(10, 2)   default(0.0), not null
#  slug               :string           not null
#  storage_mb         :integer          default(100), not null
#  trial_days         :integer          default(0), not null
#  trial_messages     :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_plans_on_is_default_trial  (is_default_trial) UNIQUE WHERE is_default_trial
#  index_plans_on_slug              (slug) UNIQUE
#

# ChatHub's own pricing/limit tiers — the single source of truth for what an
# account can use (Captain AI responses/documents, human agents, inboxes,
# outgoing email), replacing the split between Chatwoot Cloud's Stripe-driven
# plan config (JSON in InstallationConfig, see Enterprise::Billing::PlanConfiguration
# and Enterprise::Account::PlanUsageAndLimits — never applies self-hosted anyway).
#
# Deliberately a top-level, un-namespaced model — the SuperAdmin/Administrate
# sidebar resolves a resource's model class by convention from its route name
# ("plan".classify => "Plan"), and a namespaced class name breaks navigation
# rendering across all of SuperAdmin, not just this resource's own pages.
class Plan < ApplicationRecord # rubocop:disable Metrics/ClassLength
  # The complete plan-limit catalog. Existing values stay in their columns;
  # JSONB stores new limits and explicit unlimited overrides for old columns.
  LIMITS = [
    {
      key: :max_human_agents, column: :max_human_agents, group: :team,
      label_en: 'Human agents', label_es: 'Agentes humanos', unit_en: 'agents', unit_es: 'agentes',
      help_en: 'Maximum human agents in the account.', help_es: 'Máximo de agentes humanos en la cuenta.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#agent_limits'
    },
    {
      key: :max_captain_assistants, column: :max_captain_assistants, group: :ai,
      label_en: 'Captain assistants', label_es: 'Asistentes de Captain', unit_en: 'assistants', unit_es: 'asistentes',
      help_en: 'Maximum Captain assistants.', help_es: 'Máximo de asistentes de Captain.',
      enforcement: 'Captain::Assistant#ensure_within_plan_limit'
    },
    {
      key: :max_inboxes, column: :max_inboxes, group: :channels,
      label_en: 'Inboxes', label_es: 'Canales', unit_en: 'inboxes', unit_es: 'canales',
      help_en: 'Maximum inboxes.', help_es: 'Máximo de canales.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#inbox_limits'
    },
    {
      key: :max_integrations, group: :channels,
      label_en: 'Integrations', label_es: 'Integraciones', unit_en: 'integrations', unit_es: 'integraciones',
      help_en: 'Maximum integrations. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de integraciones. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :monthly_messages, column: :monthly_messages, group: :ai,
      label_en: 'AI responses', label_es: 'Respuestas de IA', unit_en: 'per month', unit_es: 'por mes',
      help_en: 'Monthly Captain response pool.', help_es: 'Bolsa mensual de respuestas de Captain.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#captain_monthly_limit'
    },
    {
      key: :captain_copilot_responses, column: :captain_copilot_responses, group: :ai,
      label_en: 'Copilot responses', label_es: 'Respuestas de Copilot', unit_en: 'per month', unit_es: 'por mes',
      help_en: 'Monthly Copilot response allowance.', help_es: 'Cupo mensual de respuestas de Copilot.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#copilot_limit'
    },
    {
      key: :captain_internal_calls, column: :captain_internal_calls, group: :ai,
      label_en: 'Internal AI calls', label_es: 'Llamadas internas de IA', unit_en: 'per month', unit_es: 'por mes',
      help_en: 'Monthly internal Captain action allowance.', help_es: 'Cupo mensual de acciones internas de Captain.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#internal_limit'
    },
    {
      key: :captain_daily_tests, column: :captain_daily_tests, group: :ai,
      label_en: 'Captain playground tests', label_es: 'Pruebas del Playground de Captain', unit_en: 'per day', unit_es: 'por día',
      help_en: 'Daily tests before using the plan response pool.',
      help_es: 'Pruebas diarias antes de usar la bolsa de respuestas del plan.',
      enforcement: 'Captain::Playground::Usage#enforce_plan_limit!'
    },
    {
      key: :max_documents, column: :max_documents, group: :storage,
      label_en: 'Documents', label_es: 'Documentos', unit_en: 'documents', unit_es: 'documentos',
      help_en: 'Maximum documents added by a Captain web crawl.',
      help_es: 'Máximo de documentos agregados por un rastreo web de Captain.',
      enforcement: 'Captain::Documents::CrawlJob#perform_firecrawl_crawl (crawl size only)'
    },
    {
      key: :storage_mb, column: :storage_mb, group: :storage,
      label_en: 'Storage', label_es: 'Almacenamiento', unit_en: 'MB', unit_es: 'MB',
      help_en: 'Captain document storage allowance.', help_es: 'Cupo de almacenamiento de documentos de Captain.',
      enforcement: 'Enterprise::Captain::Document#ensure_within_plan_limit'
    },
    {
      key: :max_synced_templates, group: :templates,
      label_en: 'Synced templates', label_es: 'Plantillas sincronizadas', unit_en: 'templates', unit_es: 'plantillas',
      help_en: 'Maximum synced message templates. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de plantillas sincronizadas. PLAN-GRATIS implementará su aplicación.',
      enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :template_sends_per_month, group: :templates,
      label_en: 'Template sends', label_es: 'Envíos de plantillas', unit_en: 'per month', unit_es: 'por mes',
      help_en: 'Monthly template sends. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Envíos mensuales de plantillas. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_flows, group: :appointments,
      label_en: 'Flows', label_es: 'Flows', unit_en: 'flows', unit_es: 'flows',
      help_en: 'Maximum Flows. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de Flows. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_appointments, group: :appointments,
      label_en: 'Appointments', label_es: 'Citas', unit_en: 'appointments', unit_es: 'citas',
      help_en: 'Maximum appointments. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de citas. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_calendars, group: :appointments,
      label_en: 'Calendars', label_es: 'Calendarios', unit_en: 'calendars', unit_es: 'calendarios',
      help_en: 'Maximum connected calendars. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de calendarios conectados. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_campaigns_per_month, group: :campaigns,
      label_en: 'Campaigns', label_es: 'Campañas', unit_en: 'per month', unit_es: 'por mes',
      help_en: 'Monthly campaign allowance. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Cupo mensual de campañas. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_emails_per_day, column: :max_emails_per_day, group: :emails,
      label_en: 'Emails', label_es: 'Correos', unit_en: 'per day', unit_es: 'por día',
      help_en: 'Daily account email allowance.', help_es: 'Cupo diario de correos de la cuenta.',
      enforcement: 'Enterprise::Account::PlanUsageAndLimits#plan_email_limit'
    },
    {
      key: :max_api_users, group: :api,
      label_en: 'API users', label_es: 'Usuarios de API', unit_en: 'users', unit_es: 'usuarios',
      help_en: 'Maximum API users. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de usuarios de API. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_automations, group: :automation,
      label_en: 'Automations', label_es: 'Automatizaciones', unit_en: 'automations', unit_es: 'automatizaciones',
      help_en: 'Maximum automations. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de automatizaciones. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :max_macros, group: :automation,
      label_en: 'Macros', label_es: 'Macros', unit_en: 'macros', unit_es: 'macros',
      help_en: 'Maximum macros. Enforcement is planned with PLAN-GRATIS.',
      help_es: 'Máximo de macros. PLAN-GRATIS implementará su aplicación.', enforcement: 'TODO PLAN-GRATIS'
    },
    {
      key: :trial_days, column: :trial_days, group: :trial,
      label_en: 'Trial duration', label_es: 'Duración de prueba', unit_en: 'days', unit_es: 'días',
      help_en: 'Trial duration included with this plan.', help_es: 'Duración de prueba incluida con este plan.',
      enforcement: 'Plan catalog/API; no runtime enforcement found'
    },
    {
      key: :trial_messages, column: :trial_messages, group: :trial,
      label_en: 'Trial responses', label_es: 'Respuestas de prueba', unit_en: 'responses', unit_es: 'respuestas',
      help_en: 'Trial response allowance.', help_es: 'Cupo de respuestas de prueba.',
      enforcement: 'Plan catalog/API; no runtime enforcement found'
    }
  ].map(&:freeze).freeze
  LIMITS_BY_KEY = LIMITS.index_by { |limit| limit[:key] }.freeze

  FEATURES = [
    {
      key: 'captain_integration', label_en: 'Captain', label_es: 'Captain',
      description_en: 'Captain AI assistants.', description_es: 'Asistentes de IA de Captain.',
      group: 'AI', flags: %w[captain_integration captain_integration_v2]
    },
    {
      key: 'captain_tasks', label_en: 'AI tools for agents', label_es: 'Herramientas de IA para agentes',
      description_en: 'Summarize, rewrite, and suggest replies with AI.',
      description_es: 'Resumir, reescribir y sugerir respuestas con IA.',
      group: 'AI', flags: %w[captain_tasks]
    },
    {
      key: 'calendar_integration', label_en: 'Calendars', label_es: 'Calendarios',
      description_en: 'Calendar integrations.', description_es: 'Integraciones de calendario.',
      group: 'Integrations', flags: %w[calendar_integration]
    },
    {
      key: 'integrations', label_en: 'Integrations', label_es: 'Integraciones',
      description_en: 'Third-party integrations.', description_es: 'Integraciones con terceros.',
      group: 'Integrations', flags: %w[integrations]
    },
    {
      key: 'flows', label_en: 'Flows', label_es: 'Flows',
      description_en: 'Conversation flows.', description_es: 'Flujos de conversación.',
      group: 'Automation', flags: %w[flows_v1]
    },
    {
      key: 'campaigns', label_en: 'Campaigns', label_es: 'Campañas',
      description_en: 'Campaigns including WhatsApp campaigns.', description_es: 'Campañas, incluidas las de WhatsApp.',
      group: 'Messaging', flags: %w[campaigns whatsapp_campaign]
    },
    {
      key: 'automations', label_en: 'Automations', label_es: 'Automatizaciones',
      description_en: 'Automation rules and delayed automations.', description_es: 'Reglas y automatizaciones programadas.',
      group: 'Automation', flags: %w[automations delayed_automations]
    },
    {
      key: 'macros', label_en: 'Macros', label_es: 'Macros',
      description_en: 'Reusable conversation actions.', description_es: 'Acciones reutilizables para conversaciones.',
      group: 'Automation', flags: %w[macros]
    },
    {
      key: 'api_and_webhooks', label_en: 'API and webhooks', label_es: 'API y webhooks',
      description_en: 'Account API and outgoing webhooks.', description_es: 'API de cuenta y webhooks salientes.',
      group: 'Integrations', flags: %w[api_and_webhooks]
    },
    {
      key: 'help_center', label_en: 'Help Center', label_es: 'Centro de ayuda',
      description_en: 'Public help center.', description_es: 'Centro de ayuda público.',
      group: 'Support', flags: %w[help_center]
    },
    {
      key: 'custom_roles', label_en: 'Custom roles', label_es: 'Roles personalizados',
      description_en: 'Fine-grained access roles.', description_es: 'Roles de acceso detallados.',
      group: 'Security', flags: %w[custom_roles]
    },
    {
      key: 'sla', label_en: 'SLA', label_es: 'SLA',
      description_en: 'Service level policies.', description_es: 'Políticas de nivel de servicio.',
      group: 'Support', flags: %w[sla]
    },
    {
      key: 'help_center_semantic_search', label_en: 'Help Center semantic search',
      label_es: 'Búsqueda semántica del Centro de ayuda',
      description_en: 'Semantic search over help articles.',
      description_es: 'Búsqueda semántica en artículos de ayuda.',
      group: 'Support', flags: %w[help_center_embedding_search]
    },
    {
      key: 'saml', label_en: 'SAML SSO', label_es: 'SSO SAML',
      description_en: 'SAML single sign-on.', description_es: 'Inicio de sesión único con SAML.',
      group: 'Security', flags: %w[saml]
    }
  ].map(&:freeze).freeze
  FEATURES_BY_KEY = FEATURES.index_by { |feature| feature[:key] }.freeze
  FEATURES_BY_FLAG = FEATURES.each_with_object({}) do |feature, map|
    feature[:flags].each { |flag| map[flag] = feature }
  end.freeze
  FEATURE_KEYS = FEATURES_BY_KEY.keys.freeze
  PLAN_FLAGS = FEATURES_BY_FLAG.keys.freeze
  BASE_FEATURES = Featurable::FEATURE_LIST.filter_map do |flag|
    next if PLAN_FLAGS.include?(flag['name'])
    next if flag['chatwoot_internal'] || flag['deprecated'] || flag['premium'] == true || flag['name'] == 'chatwoot_v4'
    next unless flag['enabled'] == true

    {
      key: flag['name'], label_en: flag['display_name'], label_es: flag['display_name'],
      description_en: flag['description'].to_s, description_es: flag['description'].to_s,
      group: flag['category'].presence || 'Other', flags: [flag['name']].freeze, base: true
    }.freeze
  end.freeze
  ACCOUNT_FEATURES = (FEATURES + BASE_FEATURES).freeze
  ACCOUNT_FEATURES_BY_KEY = ACCOUNT_FEATURES.index_by { |feature| feature[:key] }.freeze
  FEATURE_LIMITS = {
    'integrations' => :max_integrations,
    'flows' => :max_flows,
    'campaigns' => :max_campaigns_per_month,
    'automations' => :max_automations,
    'macros' => :max_macros,
    'api_and_webhooks' => :max_api_users,
    'calendar_integration' => :max_calendars
  }.freeze

  has_many :accounts, dependent: :nullify, inverse_of: :plan

  validate :valid_feature_keys
  validates :captain_daily_tests, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :captain_copilot_responses, :captain_internal_calls,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :valid_extra_limits
  validate :validate_limit_values
  validate :valid_column_limits
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  # DB partial unique index enforces this too; the validation just gives a
  # friendly SuperAdmin form error instead of a raw StatementInvalid.
  validates :is_default_trial, uniqueness: true, if: :is_default_trial?

  scope :active, -> { where(is_active: true) }
  scope :public_plans, -> { where(is_public: true) }
  scope :ordered, -> { order(:display_order, :price_monthly) }
  scope :catalog, -> { active.public_plans.where.not(slug: 'developer').order(:display_order, :id) }

  def limit(key)
    definition = LIMITS_BY_KEY.fetch(key.to_sym)
    return nil if unlimited_limit?(key)

    value = self[definition[:column]] if definition[:column]
    value.nil? ? stored_limit(key) : value
  end

  def unlimited_limit?(key)
    stored_key = limits&.key?(key.to_s) ? key.to_s : key.to_sym
    limits&.key?(stored_key) && limits[stored_key].nil?
  end

  def limit_values
    LIMITS.to_h { |definition| [definition[:key], limit(definition[:key])] }
  end

  def copilot_available?
    limit(:captain_copilot_responses) != 0
  end

  def limit_values=(values)
    @invalid_limit_values = false
    unless values.respond_to?(:each_pair)
      @invalid_limit_values = true
      return
    end

    values.each_pair { |key, value| assign_limit_value(key, value) }
  rescue ArgumentError, KeyError, TypeError
    @invalid_limit_values = true
  end

  def catalog_state
    return 'hidden' unless is_active? && is_public? && slug != 'developer'

    coming_soon? ? 'coming_soon' : 'available'
  end

  private

  def valid_extra_limits
    unless limits.is_a?(Hash)
      errors.add(:limits, :invalid)
      return
    end

    valid = limits.all? do |key, value|
      LIMITS_BY_KEY.key?(key.to_sym) && (value.nil? || (value.is_a?(Integer) && value >= 0))
    end
    return if valid

    errors.add(:limits, :invalid)
  end

  def stored_limit(key)
    stored_key = limits&.key?(key.to_s) ? key.to_s : key.to_sym
    limits&.[](stored_key)
  end

  def valid_column_limits
    LIMITS.filter_map { |definition| definition[:column] }.uniq.each do |column|
      value = self[column]
      errors.add(column, :greater_than_or_equal_to, count: 0) if value.present? && value.negative?
    end
  end

  def assign_limit_value(key, raw_value)
    definition = LIMITS_BY_KEY.fetch(key.to_sym)
    value = raw_value.to_s.empty? ? nil : Integer(raw_value.to_s, 10)
    extras = (limits || {}).dup
    if definition[:column]
      assign_column_limit(key, definition[:column], value, extras)
    else
      assign_json_limit(key, value, extras)
    end
    self.limits = extras
  end

  def assign_column_limit(key, column, value, extras)
    if value.nil?
      extras[key.to_s] = nil unless self[column].nil? && !extras.key?(key.to_s)
    else
      self[column] = value
      extras.delete(key.to_s)
    end
  end

  def assign_json_limit(key, value, extras)
    if value.nil?
      extras.delete(key.to_s)
    else
      extras[key.to_s] = value
    end
  end

  def validate_limit_values
    errors.add(:limits, :invalid) if @invalid_limit_values
  end

  def valid_feature_keys
    return if feature_keys.is_a?(Array) && feature_keys.all? { |key| FEATURE_KEYS.include?(key) }

    errors.add(:feature_keys, :inclusion)
  end

  after_update_commit :sync_account_features, if: :saved_change_to_feature_keys?

  def sync_account_features
    Plans::SyncPlanAccountsJob.perform_later(id)
  end
end
