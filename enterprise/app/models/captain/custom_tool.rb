# == Schema Information
#
# Table name: captain_custom_tools
#
#  id                :bigint           not null, primary key
#  auth_config       :jsonb
#  auth_type         :string           default("none")
#  description       :text
#  enabled           :boolean          default(TRUE), not null
#  endpoint_url      :text             not null
#  headers           :jsonb            not null
#  http_method       :string           default("GET"), not null
#  param_schema      :jsonb
#  request_template  :text
#  response_template :text
#  settings          :jsonb            not null
#  slug              :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint
#
# Indexes
#
#  index_captain_custom_tools_on_account_id           (account_id)
#  index_captain_custom_tools_on_assistant_id_and_slug  (assistant_id,slug) UNIQUE
#
class Captain::CustomTool < ApplicationRecord
  class LimitExceededError < StandardError; end

  MAX_PER_ASSISTANT = 50

  include Concerns::Toolable
  include Concerns::SafeEndpointValidatable

  self.table_name = 'captain_custom_tools'

  NAME_PREFIX = 'custom'.freeze
  NAME_SEPARATOR = '_'.freeze
  SETTING_KEYS = %w[requires_email_verification].freeze
  VERIFIED_SOURCES = %w[verified.email].freeze
  # OpenAI enforces a 64-char limit on function names. The slug is used
  # verbatim as the tool name in LLM requests, so it must fit within this limit.
  MAX_SLUG_LENGTH = 64
  COLLISION_SUFFIX_LENGTH = 7 # "_" + 6 random alphanumeric chars
  PARAM_SCHEMA_VALIDATION = {
    'type': 'array',
    'items': {
      'type': 'object',
      'properties': {
        'name': { 'type': 'string' },
        'type': { 'type': 'string' },
        'description': { 'type': 'string' },
        'required': { 'type': 'boolean' },
        'source': { 'enum': VERIFIED_SOURCES }
      },
      'required': %w[name type description],
      'if': { 'required': ['source'] },
      'then': { 'properties': { 'type': { 'const': 'string' } } },
      'additionalProperties': false
    }
  }.to_json.freeze
  SETTINGS_VALIDATION = {
    'type': 'object',
    'properties': SETTING_KEYS.index_with { { 'type': 'boolean' } },
    'additionalProperties': false
  }.to_json.freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'

  enum :http_method, %w[GET POST].index_by(&:itself), validate: true
  enum :auth_type, %w[none bearer basic api_key].index_by(&:itself), default: :none, validate: true, prefix: :auth

  encrypts :auth_config, :headers if Chatwoot.encryption_configured?

  before_validation :generate_slug
  before_create :ensure_within_limit

  validates :slug, presence: true, uniqueness: { scope: :assistant_id }, length: { maximum: MAX_SLUG_LENGTH }
  validates :title, presence: true
  validates :endpoint_url, presence: true
  validates_with JsonSchemaValidator,
                 schema: PARAM_SCHEMA_VALIDATION,
                 attribute_resolver: ->(record) { record.param_schema }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_VALIDATION,
                 attribute_resolver: ->(record) { record.settings }

  scope :enabled, -> { where(enabled: true) }

  def to_tool_metadata
    {
      id: slug,
      title: title,
      description: description,
      custom: true
    }
  end

  def requires_email_verification?
    settings['requires_email_verification'] == true || verified_email_param.present?
  end

  def verified_email_param
    param_schema.find { |param_def| param_def['source'] == 'verified.email' }&.dig('name')
  end

  def enabled_scenarios_count
    assistant.scenarios.enabled.where('tools @> ?', [slug].to_json).count
  end

  private

  def ensure_within_limit
    # Lock the assistant row to serialize concurrent creates and prevent exceeding the cap
    Captain::Assistant.lock.find(assistant_id)
    return if assistant.custom_tools.count < MAX_PER_ASSISTANT

    raise LimitExceededError, I18n.t('captain.custom_tool.limit_exceeded', limit: MAX_PER_ASSISTANT)
  end

  def generate_slug
    return if slug.present?
    return if title.blank?

    parameterized_title = title.parameterize(separator: NAME_SEPARATOR)
    base_slug = "#{NAME_PREFIX}#{NAME_SEPARATOR}#{parameterized_title}".truncate(MAX_SLUG_LENGTH, omission: '')
    self.slug = find_unique_slug(base_slug)
  end

  def find_unique_slug(base_slug)
    return base_slug unless slug_exists?(base_slug)

    truncated = base_slug.truncate(MAX_SLUG_LENGTH - COLLISION_SUFFIX_LENGTH, omission: '')
    5.times do
      slug_candidate = "#{truncated}#{NAME_SEPARATOR}#{SecureRandom.alphanumeric(6).downcase}"
      return slug_candidate unless slug_exists?(slug_candidate)
    end

    raise ActiveRecord::RecordNotUnique, I18n.t('captain.custom_tool.slug_generation_failed')
  end

  def slug_exists?(candidate)
    self.class.exists?(assistant_id: assistant_id, slug: candidate)
  end
end
