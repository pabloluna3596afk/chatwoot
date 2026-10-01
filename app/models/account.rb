# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  feature_flags_ext_1   :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  plan_id               :bigint
#  plan_started_at       :datetime
#
# Indexes
#
#  index_accounts_on_plan_id  (plan_id)
#  index_accounts_on_status   (status)
#

class Account < ApplicationRecord
  # used for multi-flag bitset columns
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable
  include AccountSettingsSchema

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze
  SUSPENSION_CATEGORIES = %w[spam non_payment other].freeze

  attr_accessor :suspension_category, :suspension_reason

  validates :name, presence: true
  # `domain` is the inbound email domain used to construct reply addresses
  # (see `inbound_email_domain`). Do not repurpose it for a website or any
  # non-mail-related domain.
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone
  validate :validate_support_email_format, if: :will_save_change_to_support_email?

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode, :captain_false_promise_harness_enabled
  store_accessor :settings, :resolved_label_key
  store_accessor :settings, :business_rules
  include AccountCaptainAutoResolve

  RESOLVED_LABEL_KEYS = %w[resolved closed sold finished].freeze

  before_validation :normalize_resolved_label_key

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  belongs_to :plan, optional: true
  has_many :account_plan_usages, dependent: :destroy_async
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :automation_rule_pending_executions, dependent: :delete_all
  has_many :macros, dependent: :destroy_async
  has_many :flows, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :saved_report_panels, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :calendar_connections, dependent: :destroy_async
  has_many :calendar_events, dependent: :destroy_async
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'

  # Virtual attribute used by the Super Admin dashboard to toggle widget branding per channel.
  # The actual values are stored on Channel::WebWidget.
  attr_accessor :web_widget_branding
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :working_hours, dependent: :destroy_async
  has_many :task_templates, dependent: :destroy_async
  has_many :internal_tasks, dependent: :destroy_async
  has_many :internal_conversations, dependent: :destroy_async
  has_many :internal_messages, dependent: :destroy_async

  has_one_attached :contacts_export
  has_one_attached :conversations_export

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }

  before_validation :validate_limit_keys
  before_validation :assign_default_plan, on: :create
  before_save :enable_captain_features_for_plan, if: -> { plan_id.present? && will_save_change_to_plan_id? }
  after_create_commit :notify_creation
  after_create_commit :seed_default_task_templates
  after_create_commit :seed_default_report_panels
  after_update_commit :clear_unread_conversation_counts_cache, if: :saved_change_to_feature_conversation_unread_counts?
  after_update_commit :restart_usage_period, if: :saved_change_to_plan_id?
  after_update :resume_delayed_automations, if: -> { saved_change_to_feature_delayed_automations? && feature_delayed_automations? }
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def all_conversation_tags
    # returns array of tags
    conversation_ids = conversations.pluck(:id)
    ActsAsTaggableOn::Tagging.includes(:tag)
                             .where(context: 'labels',
                                    taggable_type: 'Conversation',
                                    taggable_id: conversation_ids)
                             .map { |tagging| tagging.tag.name }
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def suspension_history
    internal_attributes['suspensions'] || []
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def copilot_responses_available?
    captain_limit = (captain_monthly_limit[:responses] || 0) / 2
    copilot_consumed = current_usage_period&.copilot_responses_consumed || 0
    (captain_limit - copilot_consumed) > 0
  end

  # The account's current billing-period usage row (see AccountPlanUsage),
  # anchored to `plan_started_at` and rolling monthly from there. Returns nil
  # when the account has no plan (nothing to meter — usage_limits falls back
  # to ChatwootApp.max_limit in that case).
  #
  # Lazily creates the row on first read of a new period. Safe under
  # concurrent callers (e.g. two inbound messages racing on a boundary):
  # `insert_all` + the unique index on (account_id, period_start) means only
  # one row survives, and the loser's insert is just a no-op re-select.
  def current_usage_period
    window = current_period_window
    return nil if window.nil?

    now = Time.current
    account_plan_usages.where(closed_at: nil)
                        .where('period_start <= ? AND period_end > ?', now, now)
                        .first || create_usage_period(window)
  end

  def api_and_webhooks_enabled?
    true
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  def onboarding_step
    step = custom_attributes['onboarding_step']
    return nil if step.blank?

    enrichment_key = format(Redis::Alfred::ACCOUNT_ONBOARDING_ENRICHMENT, account_id: id)
    Redis::Alfred.exists?(enrichment_key) ? 'enrichment' : step
  end

  def reset_cache_keys
    super
    clear_unread_conversation_counts_cache
  end

  def normalized_resolved_label_key
    key = resolved_label_key.presence || 'resolved'
    RESOLVED_LABEL_KEYS.include?(key.to_s) ? key.to_s : 'resolved'
  end

  def resolved_status_label_word
    I18n.t("conversations.activity.status_labels.#{normalized_resolved_label_key}")
  end

  def resolution_count_csv_header
    I18n.t("reports.resolution_count_labels.#{normalized_resolved_label_key}")
  end

  private

  # Same flags Enterprise::Account#enable_default_features turns on for
  # self-hosted enterprise, and the ones the sidebar, billing card and Captain
  # routes check. Removing a plan does not turn them off.
  def enable_captain_features_for_plan
    enable_features('captain_integration', 'captain_integration_v2')
  end

  def assign_default_plan
    self.plan_id ||= Plan.active.find_by(is_default_trial: true)&.id
    self.plan_started_at ||= Time.current if plan_id.present?
  end

  # Mid-period plan change: close the current period where it stands (no
  # proration — there's no billing yet) and reanchor so the new plan's
  # numbers apply from now. The next `current_usage_period` read lazily opens
  # the fresh period against the new anchor.
  def restart_usage_period
    now = Time.current
    account_plan_usages.where(closed_at: nil).where('period_start <= ?', now)
                        .update_all(closed_at: now, period_end: now) # rubocop:disable Rails/SkipsModelValidations
    update_column(:plan_started_at, now) # rubocop:disable Rails/SkipsModelValidations
  end

  # The [start, end) window (monthly, anchored to plan_started_at) that
  # contains `now`. Runs a short loop only on a cache miss (new period, or an
  # account whose usage row hasn't been touched in a while) — negligible cost
  # since it's bounded by months-since-anchor, not by requests.
  def current_period_window(now = Time.current)
    return nil if plan_started_at.blank?

    start = plan_started_at
    start += 1.month while start + 1.month <= now
    { start: start, end: start + 1.month }
  end

  def create_usage_period(window)
    AccountPlanUsage.insert_all(
      [{
        account_id: id,
        plan_id: plan_id,
        period_start: window[:start],
        period_end: window[:end],
        limit_responses: plan&.monthly_messages,
        limit_documents: plan&.max_documents,
        created_at: Time.current,
        updated_at: Time.current
      }],
      unique_by: :index_account_plan_usages_on_account_and_period_start
    )
    account_plan_usages.find_by(period_start: window[:start])
  end

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  def normalize_resolved_label_key
    return if resolved_label_key.nil? && !settings_changed?

    key = resolved_label_key.presence || 'resolved'
    self.resolved_label_key = RESOLVED_LABEL_KEYS.include?(key.to_s) ? key.to_s : 'resolved'
  end

  def clear_unread_conversation_counts_cache
    ::Conversations::UnreadCounts::Store.clear_account!(id)
  end

  def resume_delayed_automations
    AutomationRulePendingExecution.reschedule_paused(self)
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def validate_support_email_format
    value = attributes['support_email']
    return if value.blank?

    parsed = Mail::Address.new(value).address
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid')) if parsed.blank?
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end

  def seed_default_task_templates
    TaskTemplates::DefaultSeeder.new(account: self).perform
  end

  def seed_default_report_panels
    return unless ActiveRecord::Base.connection.table_exists?(:saved_report_panels)

    Reports::DefaultPanelsSeeder.new(account: self).perform
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
# Ensure helpers stay public after enterprise prepends (Module#public needs send).
Account.send(:public, :normalized_resolved_label_key, :resolved_status_label_word, :resolution_count_csv_header)
