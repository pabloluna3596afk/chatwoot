# == Schema Information
#
# Table name: saved_report_panels
#
#  id              :bigint           not null, primary key
#  business_hours  :boolean          default(FALSE), not null
#  custom_since    :bigint
#  custom_until    :bigint
#  date_preset     :string           default("last_7_days"), not null
#  description     :text
#  favorite        :boolean          default(FALSE), not null
#  filters         :jsonb            not null
#  name            :string           not null
#  widgets         :jsonb            not null
#  date_attribute  :string           default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint           not null
#
class SavedReportPanel < ApplicationRecord
  DATE_PRESETS = %w[today yesterday last_7_days last_30_days custom].freeze
  WIDGET_TYPES = %w[metric chart table].freeze
  ALLOWED_METRICS = %w[
    conversations_count
    contacts_count
    unique_contacts_count
    incoming_messages_count
    outgoing_messages_count
    avg_first_response_time
    avg_resolution_time
    reply_time
    resolutions_count
  ].freeze
  METRIC_SOURCES = %w[preset aggregation].freeze
  AGGREGATION_OPS = %w[count sum avg min max].freeze
  AGGREGATION_ENTITIES = %w[conversations contacts].freeze
  COLUMN_AGGREGATION_OPS = %w[sum avg count min max].freeze
  SCOPE_TYPES = %w[account agent inbox team label].freeze
  TABLE_KINDS = %w[pivot conversations contacts].freeze

  MAX_WIDGETS = 12
  MAX_FILTERS = 10
  MAX_PER_ACCOUNT = Limits::MAX_SAVED_REPORT_PANELS_PER_ACCOUNT
  # Detail-table preview caps only — aggregation / pivot measures scan the full range.
  DETAIL_CONVERSATIONS_LIMIT = 100
  DETAIL_CONTACTS_LIMIT = 200
  # Marker in filters JSON: route to Contacts::FilterService (labels + contact custom attrs)
  CONTACT_FILTER_TYPES = %w[contact contact_attribute].freeze
  # Panel date axis: blank / created_at = conversation.created_at; ca:<key> = CA date/datetime
  DATE_ATTRIBUTE_CREATED_AT = 'created_at'.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User'

  before_validation :clear_custom_range_unless_custom
  before_validation :normalize_date_attribute

  validates :name, presence: true, length: { maximum: 120 }
  validates :date_preset, inclusion: { in: DATE_PRESETS }
  validate :validate_custom_date_range
  validate :validate_date_attribute
  validate :validate_widgets
  validate :validate_filters
  validate :validate_account_limit, on: :create

  scope :ordered, -> { order(favorite: :desc, updated_at: :desc) }

  # Preview shares the persisted widget contract, without requiring a panel name.
  def validate_widget_configuration!
    validate_widgets
    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  private

  def clear_custom_range_unless_custom
    return if date_preset == 'custom'

    self.custom_since = nil
    self.custom_until = nil
  end

  def normalize_date_attribute
    self.date_attribute = date_attribute.to_s.strip
    self.date_attribute = '' if date_attribute == DATE_ATTRIBUTE_CREATED_AT
  end

  def validate_date_attribute
    attr = date_attribute.to_s
    return if attr.blank?

    errors.add(:date_attribute, 'must be blank or ca:<attribute_key>') unless attr.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)
  end

  def validate_custom_date_range
    return unless date_preset == 'custom'

    if custom_since.blank? || custom_until.blank?
      errors.add(:base, 'custom date range requires since and until')
      return
    end

    return if custom_since.to_i <= custom_until.to_i

    errors.add(:base, 'custom until must be after since')
  end

  def validate_account_limit
    return if account.blank?
    return if account.saved_report_panels.count < Limits::MAX_SAVED_REPORT_PANELS_PER_ACCOUNT

    errors.add(:base, 'panel limit reached for this account')
  end

  def validate_filters
    unless filters.is_a?(Array)
      errors.add(:filters, 'must be an array')
      return
    end

    errors.add(:filters, "cannot exceed #{MAX_FILTERS} conditions") if filters.size > MAX_FILTERS
  end

  def validate_widgets
    Reports::PanelWidgetValidator.new(self).validate
  end
end
