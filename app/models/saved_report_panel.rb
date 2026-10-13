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
  ADDITIVE_PANEL_MEASURES = %w[conversations_count resolved_conversations_count incoming_messages_count outgoing_messages_count].freeze
  PANEL_MEASURE_DISPLAYS = %w[value row_percent column_percent].freeze
  PANEL_FORMAT_KEYS = %w[type currency_symbol decimals].freeze
  PANEL_FORMAT_TYPES = %w[currency percent integer].freeze
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
  TABLE_KINDS = %w[agent_summary inbox_summary team_summary label_summary conversations contacts].freeze

  MAX_WIDGETS = 12
  MAX_FILTERS = 10
  MAX_PER_ACCOUNT = Limits::MAX_SAVED_REPORT_PANELS_PER_ACCOUNT
  # Detail-table preview caps only — aggregation / summary CA measures scan the full range.
  DETAIL_CONVERSATIONS_LIMIT = 100
  DETAIL_CONTACTS_LIMIT = 200
  # Legacy aliases (detail paths + older call sites)
  FILTERED_CONVERSATIONS_LIMIT = DETAIL_CONVERSATIONS_LIMIT
  FILTERED_CONTACTS_LIMIT = DETAIL_CONTACTS_LIMIT
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
    unless widgets.is_a?(Array)
      errors.add(:widgets, 'must be an array')
      return
    end

    if widgets.blank?
      errors.add(:widgets, 'must include at least one widget')
      return
    end

    if widgets.size > MAX_WIDGETS
      errors.add(:widgets, "cannot exceed #{MAX_WIDGETS}")
      return
    end

    widgets.each_with_index do |widget, index|
      validate_widget(widget.with_indifferent_access, index)
    end
  end

  def validate_widget(widget, index)
    type = widget[:type].to_s
    unless WIDGET_TYPES.include?(type)
      errors.add(:widgets, "invalid type at index #{index}")
      return
    end

    validate_metric_or_chart_widget(widget, index) if %w[metric chart].include?(type)

    scope_type = (widget[:scope_type].presence || 'account').to_s
    errors.add(:widgets, "invalid scope at index #{index}") unless SCOPE_TYPES.include?(scope_type)

    validate_dynamic_table_options(widget, index)
    return unless type == 'table'

    validate_table_widget(widget, index)
  end

  def validate_metric_or_chart_widget(widget, index)
    source = (widget[:source].presence || 'preset').to_s
    unless METRIC_SOURCES.include?(source)
      errors.add(:widgets, "invalid metric source at index #{index}")
      return
    end

    if source == 'aggregation'
      op = (widget[:aggregation_op].presence || 'count').to_s
      entity = (widget[:aggregation_entity].presence || 'conversations').to_s
      field = widget[:aggregation_field].to_s
      group_field = widget[:aggregation_group_field].to_s
      errors.add(:widgets, "invalid aggregation op at index #{index}") unless AGGREGATION_OPS.include?(op)
      errors.add(:widgets, "invalid aggregation entity at index #{index}") unless AGGREGATION_ENTITIES.include?(entity)
      errors.add(:widgets, "aggregation field required at index #{index}") if op != 'count' && field.blank?
      errors.add(:widgets, "invalid aggregation field at index #{index}") if field.present? && !field.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)
      if group_field.present? && !group_field.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)
        errors.add(:widgets, "invalid aggregation group field at index #{index}")
      end
      return
    end

    metric = widget[:metric].to_s
    errors.add(:widgets, "invalid metric at index #{index}") if ALLOWED_METRICS.exclude?(metric)
  end

  def validate_table_widget(widget, index)
    table_kind = (widget[:table_kind].presence || 'agent_summary').to_s
    errors.add(:widgets, "invalid table kind at index #{index}") unless TABLE_KINDS.include?(table_kind)

    columns = widget[:columns]
    return if columns.blank?

    unless columns.is_a?(Array)
      errors.add(:widgets, "invalid columns at index #{index}")
      return
    end

    allowed = case table_kind
              when 'conversations'
                %w[id contact_name status priority labels inbox assignee created_at last_activity_at]
              when 'contacts'
                %w[id name phone_number email document_number labels conversations_count assignee inbox created_at last_activity_at]
              when 'agent_summary'
                %w[rank id name conversations_count resolved_conversations_count csat_avg incoming_messages_count
                   outgoing_messages_count avg_first_response_time avg_resolution_time avg_reply_time share_percent]
              else
                %w[rank id name conversations_count resolved_conversations_count avg_first_response_time
                   avg_resolution_time avg_reply_time share_percent]
              end

    # ca:* / contact_ca:* measures; pivot expands to measure__pv__value (may include %).
    invalid = columns.map(&:to_s).reject do |key|
      allowed.include?(key) || key.match?(/\A(?:ca|contact_ca):[\p{L}\p{N}_.\-%]+\z/)
    end
    errors.add(:widgets, "invalid columns at index #{index}: #{invalid.join(', ')}") if invalid.any?

    validate_table_pivot(widget, index)

    aggregations = widget[:column_aggregations]
    return if aggregations.blank?

    unless aggregations.is_a?(Hash)
      errors.add(:widgets, "invalid column_aggregations at index #{index}")
      return
    end

    # Sanity: each aggregation key must be a selected column; ops in allow-list.
    # query_operator-style: omit keys for "none" rather than storing empty strings.
    column_set = columns.map(&:to_s)
    aggregations.each do |key, op|
      key = key.to_s
      op = op.to_s
      unless column_set.include?(key)
        errors.add(:widgets, "column_aggregations key not in columns at index #{index}: #{key}")
        next
      end
      errors.add(:widgets, "invalid column aggregation '#{op}' at index #{index}") unless COLUMN_AGGREGATION_OPS.include?(op)
    end
  end

  def validate_table_pivot(widget, index)
    pivot = widget[:pivot]
    return if pivot.blank?

    unless pivot.is_a?(Hash)
      errors.add(:widgets, "invalid pivot at index #{index}")
      return
    end

    pivot = pivot.with_indifferent_access
    attr = pivot[:column_attribute].to_s
    return if attr.blank?

    errors.add(:widgets, "invalid pivot column_attribute at index #{index}") unless attr.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)

    values = pivot[:column_values]
    if values.present?
      unless values.is_a?(Array)
        errors.add(:widgets, "invalid pivot column_values at index #{index}")
        return
      end
      errors.add(:widgets, "pivot column_values cannot exceed 12 at index #{index}") if values.size > 12
    end
  end

  def validate_dynamic_table_options(widget, index) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    pivot = widget[:pivot]
    options = %w[sort top_n column_formats measure_display]
    configured = options.any? { |key| widget.key?(key) } ||
                 (pivot.is_a?(Hash) && (pivot.key?(:row_attribute) || pivot.key?(:row_granularity)))
    return unless configured

    summary = %w[agent_summary inbox_summary team_summary label_summary].include?(widget[:table_kind].presence || 'agent_summary')
    unless widget[:type] == 'table' && summary
      errors.add(:widgets, "dynamic options require a summary table at index #{index}")
      return
    end

    if pivot.is_a?(Hash)
      row = pivot[:row_attribute]
      if pivot.key?(:row_attribute) && !(row.is_a?(String) &&
         (%w[agent inbox team label created_at].include?(row) || row.match?(/\A(?:ca|contact_ca):[\p{L}\p{N}_.\-]+\z/)))
        errors.add(:widgets, "invalid pivot row_attribute at index #{index}")
      end
      if pivot.key?(:row_granularity) && !(row == 'created_at' && %w[day week month].include?(pivot[:row_granularity]))
        errors.add(:widgets, "invalid pivot row_granularity at index #{index}")
      end
    end

    columns = widget[:columns].is_a?(Array) ? widget[:columns] : []
    unless columns.all?(String)
      errors.add(:widgets, "invalid columns at index #{index}")
      return
    end
    measures = columns - %w[id rank name]
    column_valid = lambda do |column, allowed|
      column.is_a?(String) && (allowed.include?(column) ||
        (pivot.is_a?(Hash) && pivot[:column_attribute].present? && column.include?('__pv__') && allowed.include?(column.split('__pv__', 2).first)))
    end
    if widget.key?(:sort)
      sort = widget[:sort]
      unless sort.is_a?(Hash) && (sort.keys - %w[column direction]).empty? &&
             column_valid.call(sort[:column], columns) && %w[asc desc].include?(sort[:direction])
        errors.add(:widgets, "invalid sort at index #{index}")
      end
    end
    if widget.key?(:top_n)
      top = widget[:top_n]
      pivot_measures = measures.select do |measure|
        %w[conversations_count resolved_conversations_count].include?(measure) || measure.start_with?('ca:', 'contact_ca:')
      end
      valid = top.is_a?(Hash) && (top.keys - %w[limit column include_others]).empty? &&
              top.key?(:limit) && (top[:limit].nil? || (top[:limit].is_a?(Integer) && [5, 10, 20].include?(top[:limit]))) &&
              column_valid.call(top[:column], pivot_measures) && [true, false].include?(top[:include_others])
      valid &&= !top[:include_others] || measures.none? { |key| key.start_with?('contact_ca:') }
      errors.add(:widgets, "invalid top_n at index #{index}") unless valid
    end
    %w[column_formats measure_display].each do |option|
      next unless widget.key?(option)

      map = widget[option]
      unless map.is_a?(Hash)
        errors.add(:widgets, "invalid #{option} at index #{index}")
        next
      end
      map.each do |measure, value|
        valid = measures.include?(measure)
        if option == 'measure_display'
          additive = ADDITIVE_PANEL_MEASURES.include?(measure) ||
                     measure.match?(/__(?:sum|count)(?:__eq__.+)?\z/)
          valid &&= PANEL_MEASURE_DISPLAYS.include?(value) && (value == 'value' || additive)
        else
          valid &&= value.is_a?(Hash) && (value.keys - PANEL_FORMAT_KEYS).empty? &&
                    PANEL_FORMAT_TYPES.include?(value[:type]) &&
                    (!value.key?(:currency_symbol) || value[:currency_symbol].is_a?(String)) &&
                    (!value.key?(:decimals) || (value[:decimals].is_a?(Integer) && (0..2).cover?(value[:decimals])))
        end
        errors.add(:widgets, "invalid #{option} measure at index #{index}: #{measure}") unless valid
      end
    end
  end
end
