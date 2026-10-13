class Reports::PanelRunnerService
  # ponytail: statement_timeout caps expensive panel runs; raise if panels need longer windows
  STATEMENT_TIMEOUT_MS = 15_000
  PivotResolutionContext = Struct.new(:table_kind, :attribute_key, :selected_values, :since_time, :until_time, :pivot, :name_map, keyword_init: true)
  PivotTotalsContext = Struct.new(
    :columns, :attribute_types, :footer_aggs, :buckets, :measures, :pivot_values, :all_row_values, keyword_init: true
  )

  # Filters that only affect conversation-scoped widgets. Contact custom attrs are split out.
  # Not applied: live message-content filters beyond FilterService; metric scopes other than account
  # still use widget scope_type when no panel filters are set.

  def initialize(panel:, account:, user:, timezone_offset: 0, date_overrides: {})
    @panel = panel
    @account = account
    @user = user
    @timezone_offset = timezone_offset.to_f
    @date_overrides = date_overrides
  end

  def perform
    since_time, until_time = resolve_range
    with_statement_timeout do
      {
        panel_id: @panel.id,
        name: @panel.name,
        description: @panel.description,
        date_preset: @panel.date_preset,
        custom_since: @panel.custom_since,
        custom_until: @panel.custom_until,
        date_attribute: @panel.date_attribute.to_s.presence || SavedReportPanel::DATE_ATTRIBUTE_CREATED_AT,
        since: since_time.to_i,
        until: until_time.to_i,
        business_hours: @panel.business_hours,
        widgets: @panel.widgets.map { |widget| run_widget(widget.with_indifferent_access, since_time, until_time) }
      }
    end
  end

  private

  def resolve_range
    return Reports::PanelDateRange.validate(@date_overrides[:since], @date_overrides[:until], account: @account) if @date_overrides.any?

    Reports::PanelDateRange.resolve(
      @panel.date_preset,
      custom_since: @panel.custom_since,
      custom_until: @panel.custom_until,
      account: @account
    )
  end

  def with_statement_timeout
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
      yield
    end
  end

  def run_widget(widget, since_time, until_time)
    case widget[:type].to_s
    when 'metric'
      build_metric_widget(widget, since_time, until_time)
    when 'chart'
      build_chart_widget(widget, since_time, until_time)
    when 'table'
      build_table_widget(widget, since_time, until_time)
    else
      { id: widget[:id], type: widget[:type], error: 'unsupported_widget' }
    end
  rescue StandardError => e
    { id: widget[:id], type: widget[:type], error: e.message.presence || e.class.name, rows: [], points: [], value: nil }
  end

  def build_metric_widget(widget, since_time, until_time)
    return build_aggregation_metric_widget(widget, since_time, until_time) if aggregation_source?(widget)

    metric = widget[:metric].to_s
    value =
      if metric == 'contacts_count'
        filtered_contacts_count(since_time, until_time)
      elsif metric == 'unique_contacts_count'
        unique_contacts_count(since_time, until_time)
      elsif metric == 'resolutions_count'
        widget_resolution_events_scope(widget, since_time, until_time).distinct.count(:conversation_id)
      elsif conversation_filters? || contact_filters? || panel_date_attribute_key.present?
        filtered_metric_value(metric, since_time, until_time)
      else
        report_builder(widget, since_time, until_time).summary[metric.to_sym]
      end

    {
      id: widget[:id],
      type: 'metric',
      title: widget[:title],
      metric: metric,
      source: 'preset',
      value: value
    }
  end

  def build_chart_widget(widget, since_time, until_time)
    return build_aggregation_chart_widget(widget, since_time, until_time) if aggregation_source?(widget)

    metric = widget[:metric].to_s
    group_by = widget[:group_by].presence || 'day'
    points =
      if metric == 'resolutions_count'
        resolution_chart_points(widget, since_time, until_time, group_by)
      elsif conversation_filters? || contact_filters? || panel_date_attribute_key.present?
        filtered_chart_points(metric, since_time, until_time, group_by)
      else
        report_builder(widget, since_time, until_time, metric: metric, group_by: group_by).build
      end

    {
      id: widget[:id],
      type: 'chart',
      title: widget[:title],
      metric: metric,
      source: 'preset',
      chart_kind: widget[:chart_kind].presence || 'bar',
      points: points
    }
  end

  def aggregation_source?(widget)
    widget[:source].to_s == 'aggregation'
  end

  def build_aggregation_metric_widget(widget, since_time, until_time)
    op = (widget[:aggregation_op].presence || 'count').to_s
    field = widget[:aggregation_field].to_s
    entity = (widget[:aggregation_entity].presence || 'conversations').to_s
    group_field = widget[:aggregation_group_field].to_s
    values = aggregation_field_values(entity, field, since_time, until_time, group_field: group_field, op: op)

    {
      id: widget[:id],
      type: 'metric',
      title: widget[:title],
      metric: nil,
      source: 'aggregation',
      aggregation_op: op,
      aggregation_field: field,
      aggregation_entity: entity,
      aggregation_group_field: group_field.presence,
      value: aggregate_numeric_values(values, op)
    }
  end

  def build_aggregation_chart_widget(widget, since_time, until_time)
    op = (widget[:aggregation_op].presence || 'count').to_s
    field = widget[:aggregation_field].to_s
    entity = (widget[:aggregation_entity].presence || 'conversations').to_s
    group_by = widget[:group_by].presence || 'day'
    group_field = widget[:aggregation_group_field].to_s
    # When aggregation_group_field is set (ca:fecha), bucket by that custom date/datetime
    # and sum/avg aggregation_field (ca:precio). Both are custom attributes.
    points = aggregation_chart_points(
      entity, field, op, since_time, until_time, group_by, group_field: group_field
    )

    {
      id: widget[:id],
      type: 'chart',
      title: widget[:title],
      metric: nil,
      source: 'aggregation',
      aggregation_op: op,
      aggregation_field: field,
      aggregation_entity: entity,
      aggregation_group_field: group_field.presence,
      chart_kind: widget[:chart_kind].presence || 'bar',
      points: points
    }
  end

  def aggregation_field_values(entity, field, since_time, until_time, group_field: nil, op: 'sum')
    records = aggregation_source_records(entity, since_time, until_time, group_field: group_field)

    return Array(records).map { 1 } if field.blank?

    attr_key = field.delete_prefix(CA_COLUMN_PREFIX)
    Array(records).filter_map do |record|
      attrs = record.custom_attributes || {}
      val = attrs[attr_key]
      next if custom_attr_blank?(val)

      # Count = rows where attribute is set; sum/avg/min/max need numeric parse (skip nil).
      op.to_s == 'count' ? 1 : CustomAttributes::NumericParser.parse(val)
    end
  end

  def filtered_contacts_for_aggregation(since_time, until_time)
    # Full distinct contact set for the conversation scope (no artificial cap).
    contact_ids = Conversation.where(id: filtered_conversation_ids_subquery(since_time, until_time))
                              .distinct
                              .pluck(:contact_id)
    @account.contacts.where(id: contact_ids)
  end

  def aggregate_numeric_values(values, op)
    # Count may pass 1s; sum/avg/min/max skip unparseable (nil from NumericParser).
    return Array(values).size if op.to_s == 'count'

    list = Array(values).filter_map { |v| v.is_a?(Numeric) ? v.to_f : CustomAttributes::NumericParser.parse(v) }
    return 0 if list.empty?

    case op.to_s
    when 'sum' then list.sum
    when 'avg' then list.sum.to_f / list.size
    when 'min' then list.min
    when 'max' then list.max
    else list.sum
    end
  end

  def aggregation_chart_points(entity, field, op, since_time, until_time, group_by, group_field: nil)
    timezone = timezone_name
    group_attr = group_field.present? ? group_field.to_s.delete_prefix(CA_COLUMN_PREFIX) : nil
    records = aggregation_source_records(entity, since_time, until_time, group_field: group_field)

    grouped = Array(records).group_by do |record|
      ts = record_bucket_time(record, group_attr, timezone)
      next if ts.blank?

      period_start(ts, group_by)
    end
    grouped.delete(nil)

    periods = []
    cursor = period_start(since_time.in_time_zone(timezone), group_by)
    step = period_step(group_by)
    until_zoned = until_time.in_time_zone(timezone)
    while cursor <= until_zoned
      periods << cursor
      cursor += step
    end

    attr_key = field.present? ? field.delete_prefix(CA_COLUMN_PREFIX) : nil
    periods.map do |period|
      bucket = grouped[period] || []
      values =
        if attr_key.blank?
          bucket.map { 1 }
        else
          bucket.filter_map do |record|
            attrs = record.custom_attributes || {}
            val = attrs[attr_key]
            next if custom_attr_blank?(val)

            op == 'count' ? 1 : CustomAttributes::NumericParser.parse(val)
          end
        end
      { value: aggregate_numeric_values(values, op), timestamp: period.to_i }
    end
  end

  def aggregation_source_records(entity, since_time, until_time, group_field: nil)
    group_attr = group_field.present? ? group_field.to_s.delete_prefix(CA_COLUMN_PREFIX) : nil

    if entity == 'contacts'
      records =
        if group_attr.present?
          contacts_for_attribute_date_range(since_time, until_time, group_attr)
        else
          filtered_contacts_for_aggregation(since_time, until_time)
        end
      return Array(records)
    end

    if group_attr.present?
      conversations_for_attribute_date_range(since_time, until_time, group_attr)
    else
      # Full range scan (batched) — same universe as pivot / flat CA measures.
      each_conversation_in_batches(filtered_conversations_scope(since_time, until_time))
    end
  end

  # Conversations whose custom date/datetime attribute falls in the panel range.
  # Panel filters (inbox/agent/…) still apply; created_at date filter does not.
  def conversations_for_attribute_date_range(since_time, until_time, group_attr_key)
    ids = conversation_ids_for_attribute_date_range(since_time, until_time, group_attr_key)
    conversations_matching_filters_without_date.where(id: ids).to_a
  end

  def conversation_ids_for_attribute_date_range(since_time, until_time, group_attr_key)
    cache_key = [since_time.to_i, until_time.to_i, group_attr_key]
    @conversation_ids_by_ca_date ||= {}
    return @conversation_ids_by_ca_date[cache_key] if @conversation_ids_by_ca_date.key?(cache_key)

    scope = conversations_matching_filters_without_date
             .where('custom_attributes ? :key', key: group_attr_key)
             .unscope(:order)
    ids = []
    each_conversation_in_batches(scope) do |conversation|
      ts = parse_custom_attribute_time(conversation.custom_attributes&.[](group_attr_key))
      next unless ts.present? && ts >= since_time && ts <= until_time

      ids << conversation.id
    end
    @conversation_ids_by_ca_date[cache_key] = ids
  end

  def contacts_for_attribute_date_range(since_time, until_time, group_attr_key)
    scope = @account.contacts.where('custom_attributes ? :key', key: group_attr_key)
    scope = scope.where(id: filtered_contact_ids) if contact_filters?
    matched = []
    scope.unscope(:order).in_batches(of: 250) do |batch|
      batch.each do |contact|
        ts = parse_custom_attribute_time(contact.custom_attributes&.[](group_attr_key))
        next unless ts.present? && ts >= since_time && ts <= until_time

        matched << contact
      end
    end
    matched
  end

  # Yields each conversation (or collects to array if no block). Full scan; statement_timeout caps cost.
  def each_conversation_in_batches(scope, includes: nil)
    relation = scope.unscope(:order)
    collected = block_given? ? nil : []
    relation.in_batches(of: 250) do |batch|
      records = includes.present? ? batch.includes(*Array(includes)) : batch
      records.each do |conversation|
        if block_given?
          yield conversation
        else
          collected << conversation
        end
      end
    end
    collected
  end

  def panel_date_attribute_key
    attr = @panel.date_attribute.to_s
    return nil if attr.blank? || attr == SavedReportPanel::DATE_ATTRIBUTE_CREATED_AT
    return nil unless attr.start_with?(CA_COLUMN_PREFIX)

    attr.delete_prefix(CA_COLUMN_PREFIX)
  end

  def conversations_matching_filters_without_date
    scope =
      if conversation_filter_payload.present?
        Conversations::FilterService.new(
          { payload: conversation_filter_payload },
          @user,
          @account
        ).perform[:conversations].unscope(:limit, :offset)
      else
        Conversations::PermissionFilterService.new(
          @account.conversations,
          @user,
          @account
        ).perform
      end

    scope = scope.where(contact_id: filtered_contact_ids) if contact_filters?
    scope
  end

  def record_bucket_time(record, group_attr, timezone)
    if group_attr.present?
      parse_custom_attribute_time(record.custom_attributes&.[](group_attr))&.in_time_zone(timezone)
    else
      record.created_at.in_time_zone(timezone)
    end
  end

  def parse_custom_attribute_time(value)
    return value if value.is_a?(Time) || value.is_a?(DateTime)
    return value.to_time if value.is_a?(Date)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def period_start(ts, group_by)
    case group_by
    when 'week' then ts.beginning_of_week
    when 'month' then ts.beginning_of_month
    when 'year' then ts.beginning_of_year
    when 'hour' then ts.beginning_of_hour
    else ts.beginning_of_day
    end
  end

  def period_step(group_by)
    case group_by
    when 'week' then 1.week
    when 'month' then 1.month
    when 'year' then 1.year
    when 'hour' then 1.hour
    else 1.day
    end
  end

  CA_COLUMN_PREFIX = 'ca:'.freeze
  CONTACT_CA_COLUMN_PREFIX = 'contact_ca:'.freeze
  SUMMARY_TABLE_KINDS = %w[agent_summary inbox_summary team_summary label_summary].freeze
  # Bake aggregation into column id: ca:ventas__sum / ca:ventas__count (see panelConstants.js)
  # Optional legacy value match: ca:estado__count__eq__venta
  # Pivot segment: conversations_count__pv__venta / ca:ventas__sum__pv__Plan%20Pro
  MEASURE_OPS = %w[count sum avg min max].freeze
  MEASURE_SEP = '__'.freeze
  MEASURE_FILTER_EQ = 'eq'.freeze
  PIVOT_SEP = '__pv__'.freeze
  PIVOT_BLANK = '__blank__'.freeze
  MAX_PIVOT_ROWS = 1_000
  MAX_PIVOT_BUCKETS = 12_000
  MAX_PIVOT_VALUES = 12
  PIVOT_IDENTITY_COLUMNS = %w[rank name id].freeze
  PIVOT_SYSTEM_MEASURES = %w[conversations_count resolved_conversations_count].freeze
  # Synthetic agent row for conversations with assignee_id NULL (never a real user id).
  UNASSIGNED_AGENT_ID = 0

  def build_table_widget(widget, since_time, until_time)
    table_kind = (widget[:table_kind].presence || 'agent_summary').to_s
    columns = Array(widget[:columns]).map(&:to_s)
    column_aggregations = (widget[:column_aggregations].presence || {}).with_indifferent_access

    if SUMMARY_TABLE_KINDS.include?(table_kind) && pivot_configured?(widget)
      return build_pivot_summary_table(widget, table_kind, columns, column_aggregations, since_time, until_time)
    end

    attribute_types = custom_attribute_type_map_for(table_kind, columns)

    rows =
      case table_kind
      when 'inbox_summary'
        enrich_named_rows(
          filtered_or_builder_summary(V2::Reports::InboxSummaryBuilder, :inbox_id, since_time, until_time, type: :inbox),
          name_map: @account.inboxes.pluck(:id, :name).to_h,
          extra_maps: summary_custom_attribute_maps(table_kind, columns, since_time, until_time, column_aggregations)
        )
      when 'team_summary'
        enrich_named_rows(
          filtered_or_builder_summary(V2::Reports::TeamSummaryBuilder, :team_id, since_time, until_time, type: :team),
          name_map: @account.teams.pluck(:id, :name).to_h,
          extra_maps: summary_custom_attribute_maps(table_kind, columns, since_time, until_time, column_aggregations)
        )
      when 'label_summary'
        enrich_named_rows(
          filtered_or_label_summary(since_time, until_time),
          name_map: @account.labels.pluck(:id, :title).to_h,
          extra_maps: summary_custom_attribute_maps(table_kind, columns, since_time, until_time, column_aggregations)
        )
      when 'conversations'
        filtered_conversation_rows(since_time, until_time, columns)
      when 'contacts'
        filtered_contact_rows(since_time, until_time, columns)
      else
        enrich_named_rows(
          with_unassigned_agent_row(
            filtered_or_builder_summary(V2::Reports::AgentSummaryBuilder, :assignee_id, since_time, until_time, type: :agent),
            since_time,
            until_time
          ),
          name_map: agent_name_map,
          extra_maps: agent_extra_column_maps(since_time, until_time).merge(
            summary_custom_attribute_maps(table_kind, columns, since_time, until_time, column_aggregations)
          )
        )
      end

    total_count =
      case table_kind
      when 'conversations'
        filtered_conversations_scope(since_time, until_time).count
      when 'contacts'
        unique_contacts_count(since_time, until_time)
      else
        rows.size
      end

    resolved_columns = columns.presence || rows.first&.keys&.map(&:to_s) || []
    detail_table = %w[conversations contacts].include?(table_kind)
    totals = build_table_totals(rows, resolved_columns, total_count, attribute_types, column_aggregations)
    if widget[:sort] || widget[:measure_display].present?
      rows = rows.map(&:stringify_keys)
      measures = resolved_columns - PIVOT_IDENTITY_COLUMNS
      apply_panel_percentages!(rows, rows, measures, [], widget, totals)
      default_measure = measures.include?('conversations_count') ? 'conversations_count' : measures.first
      sort = widget[:sort] || { column: default_measure, direction: 'desc' }
      rows = sort_panel_rows(rows, sort[:column], sort[:direction])
    end

    {
      id: widget[:id],
      type: 'table',
      title: widget[:title],
      table_kind: table_kind,
      columns: resolved_columns,
      rows: rows,
      total_count: total_count,
      truncated: detail_table && rows.size < total_count,
      attribute_types: attribute_types,
      totals: totals
    }
  end

  def pivot_configured?(widget)
    pivot = (widget[:pivot].presence || {}).with_indifferent_access
    pivot[:column_attribute].to_s.start_with?(CA_COLUMN_PREFIX) || pivot[:row_attribute].present? ||
      widget.key?(:top_n)
  end

  # Excel-style pivot: rows = agent/inbox/team/label, columns = CA values, values = measures.
  def build_pivot_summary_table(widget, table_kind, columns, column_aggregations, since_time, until_time)
    pivot = (widget[:pivot].presence || {}).with_indifferent_access
    pivot_attr_key = pivot[:column_attribute].to_s.delete_prefix(CA_COLUMN_PREFIX)
    error = if pivot_attr_key.blank? && !dynamic_pivot_options?(widget)
              'pivot_attribute_required'
            elsif pivot_attr_key.present? && !known_custom_attribute_key?(pivot_attr_key, :conversation_attribute)
              'unknown_pivot_attribute'
            end
    return { id: widget[:id], type: 'table', title: widget[:title], table_kind: table_kind, error: error, rows: [], columns: [] } if error

    validate_pivot_row_attribute!(pivot)
    crossed = pivot_attr_key.present?
    dimension_kind = %w[agent inbox team label].include?(pivot[:row_attribute]) ? "#{pivot[:row_attribute]}_summary" : table_kind
    measures = columns.reject do |column|
      PIVOT_IDENTITY_COLUMNS.include?(column) || column.start_with?('avg_') ||
        %w[csat_avg share_percent incoming_messages_count outgoing_messages_count].include?(column)
    end
    measures = %w[conversations_count] if measures.empty?
    show_row_totals = !crossed || ActiveModel::Type::Boolean.new.cast(pivot.fetch(:show_row_totals, true))

    selected_values = crossed ? Array(pivot[:column_values]).map(&:to_s).reject(&:blank?).first(MAX_PIVOT_VALUES) : []
    pivot_values, buckets, name_map = accumulate_pivot_buckets(
      dimension_kind, pivot_attr_key, measures, selected_values, since_time, until_time, pivot
    )

    expanded_columns = []
    expanded_columns << 'name' if columns.include?('name') || columns.blank?
    expanded_columns << 'rank' if columns.include?('rank')
    if crossed
      pivot_values.each do |pval|
        measures.each { |m| expanded_columns << pivot_column_key(m, pval) }
      end
    end
    measures.each { |m| expanded_columns << m } if show_row_totals

    rows = build_pivot_rows(
      buckets, name_map, measures, pivot_values, show_row_totals, expanded_columns,
      preserve_blank_names: custom_pivot_rows?(pivot), all_row_values: dynamic_pivot_options?(widget)
    )
    attribute_types = custom_attribute_type_map_for(table_kind, measures)
    if dynamic_pivot_options?(widget)
      definitions = @account.custom_attribute_definitions.index_by { |definition| [definition.attribute_key, definition.contact_attribute?] }
      measures.each do |measure|
        next unless summary_ca_column?(measure)

        key, _op, contact, = parse_summary_ca_column(measure)
        definition = definitions[[key, contact]]
        attribute_types[measure] = definition.attribute_display_type if definition
      end
    end
    measures.each do |m|
      (crossed ? pivot_values : []).each do |pval|
        attribute_types[pivot_column_key(m, pval)] = attribute_types[m] || attribute_types[custom_attribute_key_from_measure(m)]
      end
    end

    footer_aggs = {}
    if show_row_totals
      measures.each do |m|
        op = (column_aggregations[m].presence || pivot_footer_op(m)).to_s
        footer_aggs[m] = op if SavedReportPanel::COLUMN_AGGREGATION_OPS.include?(op)
      end
    end
    (crossed ? pivot_values : []).each do |pval|
      measures.each do |m|
        col = pivot_column_key(m, pval)
        op = (column_aggregations[m].presence || pivot_footer_op(m)).to_s
        footer_aggs[col] = op if SavedReportPanel::COLUMN_AGGREGATION_OPS.include?(op)
      end
    end

    totals_context = PivotTotalsContext.new(
      columns: expanded_columns, attribute_types: attribute_types, footer_aggs: footer_aggs,
      buckets: buckets, measures: measures, pivot_values: pivot_values, all_row_values: dynamic_pivot_options?(widget)
    )

    totals = build_pivot_totals(rows, totals_context)
    total_count = rows.size
    if dynamic_pivot_options?(widget)
      rows = prepare_dynamic_pivot_rows(rows, buckets, measures, pivot_values, widget, totals)
      rows.each { |row| row.slice!(*(expanded_columns + %w[id name rank is_others])) }
    end
    metadata = {
      column_attribute: crossed ? "ca:#{pivot_attr_key}" : '', column_values: crossed ? pivot_values : [],
      measures: measures, show_row_totals: show_row_totals
    }
    metadata[:row_attribute] = pivot[:row_attribute] if pivot[:row_attribute].present?
    metadata[:row_granularity] = pivot.fetch(:row_granularity, 'day') if pivot[:row_attribute] == 'created_at'

    {
      id: widget[:id],
      type: 'table',
      title: widget[:title],
      table_kind: table_kind,
      columns: expanded_columns,
      rows: rows,
      total_count: total_count,
      attribute_types: attribute_types,
      pivot: metadata,
      totals: totals
    }
  end

  def pivot_column_key(measure, value)
    encoded = value.blank? ? PIVOT_BLANK : CGI.escape(value.to_s).gsub('+', '%20')
    "#{measure}#{PIVOT_SEP}#{encoded}"
  end

  def custom_pivot_rows?(pivot)
    pivot[:row_attribute].present? && %w[agent inbox team label].exclude?(pivot[:row_attribute])
  end

  def validate_pivot_row_attribute!(pivot)
    attribute = pivot[:row_attribute].to_s
    return unless attribute.start_with?(CA_COLUMN_PREFIX, CONTACT_CA_COLUMN_PREFIX)

    contact = attribute.start_with?(CONTACT_CA_COLUMN_PREFIX)
    key = attribute.delete_prefix(contact ? CONTACT_CA_COLUMN_PREFIX : CA_COLUMN_PREFIX)
    model = contact ? :contact_attribute : :conversation_attribute
    raise CustomExceptions::InvalidPanelPivot, 'unknown_pivot_row_attribute' unless known_custom_attribute_key?(key, model)
  end

  def dynamic_pivot_options?(widget)
    widget.dig(:pivot, :row_attribute).present? || %w[sort top_n measure_display].any? { |key| widget.key?(key) }
  end

  # Nulls always last, regardless of direction.
  def panel_nil_order(left, right)
    return 0 if left.nil? == right.nil?

    left.nil? ? 1 : -1
  end

  def sort_panel_rows(rows, column, direction) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows.sort do |left, right|
      a = left[column]
      b = right[column]
      comparison = if a.nil? || b.nil?
                     panel_nil_order(a, b)
                   else
                     value = a.is_a?(Numeric) && b.is_a?(Numeric) ? a <=> b : a.to_s <=> b.to_s
                     direction == 'desc' ? -value : value
                   end
      comparison.zero? ? left['id'].to_s <=> right['id'].to_s : comparison
    end
  end

  def prepare_dynamic_pivot_rows(rows, buckets, measures, values, widget, totals) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
    default_measure = measures.include?('conversations_count') ? 'conversations_count' : measures.first
    # Hidden row totals are also usable as saved sort/Top N measures.
    rows.each do |row|
      measures.each do |measure|
        row[measure] ||= combine_pivot_measure(buckets[row['id']].values.map { |cell| cell[measure] }, measure)
      end
    end
    top = widget[:top_n]
    selected = rows
    if top && top[:limit]
      selected = sort_panel_rows(rows, top[:column], 'desc').first(top[:limit])
      excluded = rows - selected
      if top[:include_others] && excluded.any?
        all_values = excluded.flat_map { |row| buckets[row['id']].keys }.uniq
        cells = all_values.index_with do |value|
          measures.to_h do |measure|
            accumulators = excluded.filter_map { |row| buckets[row['id']].fetch(value, {})[measure] }
            [measure, merge_pivot_accumulators(accumulators, measure)]
          end
        end
        others = build_pivot_rows(
          { '__others__' => cells }, { '__others__' => '' }, measures, values, true, [], all_row_values: true
        ).first
        others['is_others'] = true
        selected += [others]
      end
    end
    apply_panel_percentages!(rows, selected, measures, values, widget, totals)
    date_rows = widget.dig(:pivot, :row_attribute) == 'created_at'
    sort = widget[:sort] || { column: date_rows ? 'name' : default_measure, direction: date_rows ? 'asc' : 'desc' }
    regular, others = selected.partition { |row| !row['is_others'] }
    (sort_panel_rows(regular, sort[:column], sort[:direction]) + others).each_with_index do |row, index|
      row['rank'] = index + 1
    end
  end

  def apply_panel_percentages!(population, selected, measures, values, widget, totals) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
    crossed = widget.dig(:pivot, :column_attribute).present?
    displays = widget[:measure_display] || {}
    measures.each do |measure|
      mode = displays[measure]
      next unless %w[row_percent column_percent].include?(mode)

      columns = crossed ? values.map { |value| pivot_column_key(measure, value) } : [measure]
      denominators = (columns + [measure]).uniq.index_with do |column|
        population.sum { |row| row[column].to_f }
      end
      selected.each do |row|
        row_total = row[measure].to_f
        (columns + [measure]).uniq.each do |column|
          denominator = mode == 'row_percent' ? row_total : denominators[column]
          row[column] = denominator.zero? ? nil : (row[column].to_f / denominator * 100).round(2)
        end
      end
      grand_total = denominators[measure]
      (columns + [measure]).uniq.each do |column|
        next unless totals[:columns].key?(column)

        denominator = mode == 'row_percent' ? grand_total : denominators[column]
        totals[:columns][column] = denominator.zero? ? nil : (denominators[column] / denominator * 100).round(2)
      end
    end
  end

  def custom_attribute_key_from_measure(measure)
    attr_key, _op, _contact, _fop, _fv = parse_summary_ca_column(measure)
    attr_key
  end

  def accumulate_pivot_buckets(table_kind, pivot_attr_key, measures, selected_values, since_time, until_time, pivot) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
    name_map =
      case table_kind.to_s
      when 'inbox_summary' then @account.inboxes.pluck(:id, :name).to_h
      when 'team_summary' then @account.teams.pluck(:id, :name).to_h
      when 'label_summary' then @account.labels.pluck(:id, :title).to_h
      else agent_name_map
      end

    name_map = {} if custom_pivot_rows?(pivot)
    bucket_count = 0
    # Limits apply at allocation, including discovered columns beyond the visible twelve.
    buckets = Hash.new do |rows, dim|
      if pivot[:row_attribute].present? && rows.size >= MAX_PIVOT_ROWS
        raise CustomExceptions::InvalidPanelPivot, 'pivot_row_limit_exceeded: reduce the date range or filters'
      end

      rows[dim] = Hash.new do |cells, pv|
        bucket_count += 1
        if pivot[:row_attribute].present? && bucket_count > MAX_PIVOT_BUCKETS
          raise CustomExceptions::InvalidPanelPivot, 'pivot_bucket_limit_exceeded: reduce the date range or filters'
        end

        cells[pv] = new_pivot_measure_accum(measures)
      end
    end
    seen_contacts = Hash.new { |h, dim| h[dim] = Hash.new { |h2, pv| h2[pv] = {} } }
    discovered = {}

    # Keep the same row universe as the flat (non-pivot) summary — agents/inboxes/…
    # with zeros — instead of only dimensions that appear in the pivot scan.
    unless custom_pivot_rows?(pivot)
      pivot_baseline_dimension_ids(table_kind, since_time, until_time).each do |dim_id|
        buckets[dim_id]
      end
    end

    # ponytail: full range scan (batched). Old reorder(:id).limit(2k) biased to earliest
    # conversations and dropped most agents in busy accounts; statement_timeout caps cost.
    each_conversation_in_batches(filtered_conversations_scope(since_time, until_time), includes: :contact) do |conversation|
      dim_ids = pivot_dimension_ids(table_kind, conversation, pivot, name_map)
      next if dim_ids.empty?

      raw_val = conversation.custom_attributes&.[](pivot_attr_key)
      pivot_val = normalize_pivot_value(raw_val)
      next if selected_values.present? && selected_values.exclude?(pivot_val) && !(pivot_val.blank? && selected_values.include?(''))

      discovered[pivot_val] = true
      dim_ids.each do |dim_id|
        accum = buckets[dim_id][pivot_val]
        accumulate_pivot_measures!(accum, conversation, measures, seen_contacts[dim_id][pivot_val])
      end
    end

    if measures.include?('resolved_conversations_count')
      context = PivotResolutionContext.new(
        table_kind: table_kind, attribute_key: pivot_attr_key, selected_values: selected_values,
        since_time: since_time, until_time: until_time, pivot: pivot, name_map: name_map
      )
      accumulate_pivot_resolutions!(buckets, discovered, context)
    end

    pivot_values =
      if selected_values.present?
        selected_values
      else
        # Prefer list definition order, then discovered
        defined = @account.custom_attribute_definitions.find_by(
          attribute_key: pivot_attr_key, attribute_model: :conversation_attribute
        )&.attribute_values
        ordered = Array(defined).map(&:to_s) & discovered.keys.map(&:to_s)
        rest = discovered.keys.map(&:to_s) - ordered
        (ordered + rest).first(MAX_PIVOT_VALUES)
      end
    pivot_values = discovered.keys.map(&:to_s).first(MAX_PIVOT_VALUES) if pivot_values.empty?

    pivot_values = [''] if pivot_attr_key.blank?
    [pivot_values, buckets, name_map]
  end

  def accumulate_pivot_resolutions!(buckets, discovered, context)
    events = resolution_events_scope(context.since_time, context.until_time)
    if context.pivot[:row_attribute] == 'created_at'
      events = events.where(conversation_id: filtered_conversation_ids_subquery(context.since_time, context.until_time))
    end
    events.includes(conversation: :contact).find_each do |event|
      conversation = event.conversation
      pivot_val = normalize_pivot_value(conversation.custom_attributes&.[](context.attribute_key))
      next if context.selected_values.present? && context.selected_values.exclude?(pivot_val)

      dim_ids = pivot_resolution_dimension_ids(context.table_kind, event, context.pivot, context.name_map)
      discovered[pivot_val] = true if dim_ids.present?
      dim_ids.each do |dim_id|
        buckets[dim_id][pivot_val]['resolved_conversations_count'][conversation.id] = true
      end
    end
  end

  def pivot_resolution_dimension_ids(table_kind, event, pivot, name_map)
    return pivot_dimension_ids(table_kind, event.conversation, pivot, name_map) if custom_pivot_rows?(pivot)

    case table_kind.to_s
    when 'agent_summary' then [event.user_id || UNASSIGNED_AGENT_ID]
    when 'inbox_summary' then [event.inbox_id].compact
    else pivot_dimension_ids(table_kind, event.conversation)
    end
  end

  # Same dimension ids the flat summary table would show for this kind/filters/range.
  def pivot_baseline_dimension_ids(table_kind, since_time, until_time)
    rows =
      case table_kind.to_s
      when 'inbox_summary'
        filtered_or_builder_summary(V2::Reports::InboxSummaryBuilder, :inbox_id, since_time, until_time, type: :inbox)
      when 'team_summary'
        filtered_or_builder_summary(V2::Reports::TeamSummaryBuilder, :team_id, since_time, until_time, type: :team)
      when 'label_summary'
        filtered_or_label_summary(since_time, until_time)
      else
        with_unassigned_agent_row(
          filtered_or_builder_summary(V2::Reports::AgentSummaryBuilder, :assignee_id, since_time, until_time, type: :agent),
          since_time,
          until_time
        )
      end

    Array(rows).filter_map { |row| row.with_indifferent_access[:id] }
  end

  def new_pivot_measure_accum(measures)
    measures.each_with_object({}) do |m, memo|
      _attr, op, = parse_summary_ca_column(m)
      memo[m] = if m == 'resolved_conversations_count'
                  {}
                elsif op == 'avg'
                  { sum: 0.0, count: 0 }
                elsif %w[min max].include?(op)
                  []
                elsif op == 'sum'
                  0.0
                else
                  0
                end
    end
  end

  def accumulate_pivot_measures!(accum, conversation, measures, seen_contact_ids)
    measures.each do |measure|
      if measure == 'conversations_count'
        accum[measure] = accum[measure].to_i + 1
        next
      end
      next if measure == 'resolved_conversations_count'
      next unless summary_ca_column?(measure)

      attr_key, op, contact_attr, filter_op, filter_value = parse_summary_ca_column(measure)
      op = (op.presence || 'count').to_s
      if contact_attr
        contact = conversation.contact
        next if contact.blank?

        seen_contact_ids[measure] ||= {}
        next if seen_contact_ids[measure][contact.id]

        seen_contact_ids[measure][contact.id] = true
        val = contact.custom_attributes&.[](attr_key)
      else
        val = conversation.custom_attributes&.[](attr_key)
      end
      next if custom_attr_blank?(val)
      next unless custom_attr_matches_filter?(val, filter_op, filter_value)

      case op
      when 'count'
        accum[measure] = accum[measure].to_i + 1
      when 'sum'
        num = CustomAttributes::NumericParser.parse(val)
        accum[measure] = accum[measure].to_f + num if num
      when 'avg'
        num = CustomAttributes::NumericParser.parse(val)
        if num
          accum[measure][:sum] += num
          accum[measure][:count] += 1
        end
      when 'min', 'max'
        num = CustomAttributes::NumericParser.parse(val)
        accum[measure] << num if num
      end
    end
  end

  def finalize_pivot_measure(accum_value, measure)
    return (accum_value || {}).size if measure == 'resolved_conversations_count'

    _attr, op, = parse_summary_ca_column(measure)
    op = op.presence || 'count'
    if op == 'avg'
      return nil if accum_value.nil? || accum_value[:count].zero?

      return (accum_value[:sum] / accum_value[:count]).round(2)
    end
    if accum_value.is_a?(Array)
      return nil if accum_value.empty?

      result = aggregate_numeric_values(accum_value, op)
      return result.is_a?(Float) ? result.round(2) : result
    end
    val = accum_value || 0
    val.is_a?(Float) ? val.round(2) : val
  end

  def pivot_dimension_ids(table_kind, conversation, pivot = {}, name_map = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    if custom_pivot_rows?(pivot)
      attribute = pivot[:row_attribute]
      if attribute == 'created_at'
        day = conversation.created_at.getlocal((@timezone_offset * 3600).to_i).to_date
        day = day.beginning_of_week(:monday) if pivot[:row_granularity] == 'week'
        day = day.beginning_of_month if pivot[:row_granularity] == 'month'
        value = day.iso8601
      else
        contact = attribute.start_with?(CONTACT_CA_COLUMN_PREFIX)
        key = attribute.delete_prefix(contact ? CONTACT_CA_COLUMN_PREFIX : CA_COLUMN_PREFIX)
        attrs = contact ? conversation.contact&.custom_attributes : conversation.custom_attributes
        value = normalize_pivot_value(attrs&.[](key))
      end
      id = "#{attribute}:#{value.empty? ? PIVOT_BLANK : "value:#{CGI.escape(value)}"}"
      name_map[id] = value
      return [id]
    end

    case table_kind.to_s
    when 'inbox_summary'
      conversation.inbox_id.present? ? [conversation.inbox_id] : []
    when 'team_summary'
      conversation.team_id.present? ? [conversation.team_id] : []
    when 'label_summary'
      titles = conversation.cached_label_list.to_s.split(',').map(&:strip).reject(&:blank?)
      titles.filter_map { |t| labels_by_title[t]&.id }
    else
      conversation.assignee_id.present? ? [conversation.assignee_id] : [UNASSIGNED_AGENT_ID]
    end
  end

  def labels_by_title
    @labels_by_title ||= @account.labels.index_by(&:title)
  end

  def normalize_pivot_value(raw)
    return '' if raw.nil? || raw == ''
    return raw.map(&:to_s).reject(&:blank?).first.to_s if raw.is_a?(Array)

    raw.to_s
  end

  def build_pivot_rows(buckets, name_map, measures, pivot_values, show_row_totals, expanded_columns, # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
                       preserve_blank_names: false, all_row_values: false)
    sort_measure = measures.include?('conversations_count') ? 'conversations_count' : measures.first
    dim_ids = buckets.keys.sort_by do |id|
      -pivot_values.sum do |pv|
        cell = buckets[id][pv]
        next 0 if cell.blank?

        finalize_pivot_measure(cell[sort_measure], sort_measure).to_i
      end
    end

    dim_ids.map.with_index(1) do |dim_id, rank|
      # String keys only — pivot columns and totals also use strings (B-NEW-19).
      row = {
        'id' => dim_id,
        'rank' => rank,
        'name' => preserve_blank_names && name_map.key?(dim_id) ? name_map[dim_id] : name_map[dim_id].presence || "##{dim_id}"
      }
      pivot_values.each do |pval|
        cell = buckets[dim_id][pval] || {}
        measures.each do |m|
          finalized = finalize_pivot_measure(cell[m], m)
          row[pivot_column_key(m, pval)] = finalized
        end
      end

      if show_row_totals
        measures.each do |m|
          cells = all_row_values ? buckets[dim_id].values : pivot_values.map { |pv| buckets[dim_id][pv] }
          row[m] = combine_pivot_measure(cells.map { |cell| cell[m] }, m)
        end
      end

      expanded_columns.each do |col|
        next if PIVOT_IDENTITY_COLUMNS.include?(col.to_s)

        row[col] = finalize_pivot_measure(new_pivot_measure_accum([col])[col], col) unless row.key?(col)
      end
      row
    end
  end

  def merge_pivot_accumulators(accumulators, measure)
    _attr, op, = parse_summary_ca_column(measure)
    if measure == 'resolved_conversations_count'
      accumulators.compact.each_with_object({}) { |values, total| total.merge!(values) }
    elsif op == 'avg'
      accumulators.compact.each_with_object({ sum: 0.0, count: 0 }) do |values, total|
        total[:sum] += values[:sum]
        total[:count] += values[:count]
      end
    elsif %w[min max].include?(op)
      accumulators.compact.flatten
    else
      accumulators.compact.sum
    end
  end

  def combine_pivot_measure(accumulators, measure)
    finalize_pivot_measure(merge_pivot_accumulators(accumulators, measure), measure)
  end

  def pivot_footer_op(measure)
    _attr, op, = parse_summary_ca_column(measure)
    %w[avg min max].include?(op) ? op : 'sum'
  end

  def build_pivot_totals(rows, context)
    totals = build_table_totals(rows, context.columns, rows.size, context.attribute_types, context.footer_aggs)
    context.measures.each do |measure|
      update_pivot_measure_totals!(totals, measure, context)
    end
    totals
  end

  def update_pivot_measure_totals!(totals, measure, context)
    op = raw_pivot_footer_op(measure)
    return if op.nil?

    ([nil] + context.pivot_values).each do |pivot_value|
      column = pivot_value.nil? ? measure : pivot_column_key(measure, pivot_value)
      next unless context.footer_aggs[column] == op

      accumulators = pivot_total_accumulators(context, measure, pivot_value)
      totals[:columns][column] = combine_pivot_measure(accumulators, measure)
    end
  end

  def raw_pivot_footer_op(measure)
    return 'sum' if measure == 'resolved_conversations_count'

    'avg' if pivot_footer_op(measure) == 'avg'
  end

  def pivot_total_accumulators(context, measure, pivot_value)
    return context.buckets.values.flat_map { |cells| cells.values.map { |cell| cell[measure] } } if pivot_value.nil? && context.all_row_values

    values = pivot_value.nil? ? context.pivot_values : [pivot_value]
    context.buckets.values.flat_map { |cells| values.map { |value| cells[value][measure] } }
  end

  # Sum/avg/min/max/count custom attrs onto summary dimensions (agent/inbox/team/label).
  # ca:* reads conversation.custom_attributes; contact_ca:* reads contact (deduped per contact).
  # Column ids may bake the op: ca:ventas__sum + ca:ventas__count as separate columns.
  # Optional value match: ca:estado__count__eq__venta (URI-encoded).
  # Count without filter = conversations/contacts where the attribute is present (non-nil / non-empty).
  def summary_custom_attribute_maps(table_kind, columns, since_time, until_time, column_aggregations = {})
    return {} unless SUMMARY_TABLE_KINDS.include?(table_kind.to_s)

    ca_columns = Array(columns).map(&:to_s).select { |col| summary_ca_column?(col) }
    return {} if ca_columns.empty?

    maps = {}
    ca_columns.each do |col|
      _attr_key, baked_op, _contact, _filter_op, _filter_value = parse_summary_ca_column(col)
      op = (column_aggregations[col].presence || baked_op.presence || 'sum').to_s
      op = 'sum' unless SavedReportPanel::COLUMN_AGGREGATION_OPS.include?(op)
      maps[col] = aggregate_custom_attr_by_dimension(table_kind, col, op, since_time, until_time)
    end
    maps
  end

  def summary_ca_column?(col)
    col.start_with?(CA_COLUMN_PREFIX) || col.start_with?(CONTACT_CA_COLUMN_PREFIX)
  end

  # Returns [attribute_key, measure_op_or_nil, contact_attr?, filter_op_or_nil, filter_value_or_nil]
  def parse_summary_ca_column(column)
    col = column.to_s
    contact_attr = col.start_with?(CONTACT_CA_COLUMN_PREFIX)
    rest = col.delete_prefix(CONTACT_CA_COLUMN_PREFIX).delete_prefix(CA_COLUMN_PREFIX)

    filtered = rest.match(/\A(.+)#{Regexp.escape(MEASURE_SEP)}(#{MEASURE_OPS.join('|')})#{Regexp.escape(MEASURE_SEP)}#{MEASURE_FILTER_EQ}#{Regexp.escape(MEASURE_SEP)}(.+)\z/)
    return [filtered[1], filtered[2], contact_attr, MEASURE_FILTER_EQ, decode_measure_filter_value(filtered[3])] if filtered

    op = nil
    MEASURE_OPS.each do |candidate|
      suffix = "#{MEASURE_SEP}#{candidate}"
      next unless rest.end_with?(suffix) && rest.length > suffix.length

      op = candidate
      rest = rest.delete_suffix(suffix)
      break
    end
    [rest, op, contact_attr, nil, nil]
  end

  def decode_measure_filter_value(encoded)
    URI.decode_www_form_component(encoded.to_s)
  rescue ArgumentError
    encoded.to_s
  end

  def aggregate_custom_attr_by_dimension(table_kind, column, op, since_time, until_time)
    attr_key, _baked_op, contact_attr, filter_op, filter_value = parse_summary_ca_column(column)
    return {} unless known_custom_attribute_key?(attr_key, contact_attr ? :contact_attribute : :conversation_attribute)

    case table_kind.to_s
    when 'label_summary'
      aggregate_custom_attr_by_label(
        attr_key, op, since_time, until_time,
        contact_attr: contact_attr, filter_op: filter_op, filter_value: filter_value
      )
    else
      dimension = summary_dimension_column(table_kind)
      return {} if dimension.blank?

      aggregate_custom_attr_by_sql_dimension(
        dimension, attr_key, op, since_time, until_time,
        contact_attr: contact_attr, filter_op: filter_op, filter_value: filter_value
      )
    end
  end

  def summary_dimension_column(table_kind)
    case table_kind.to_s
    when 'agent_summary' then 'assignee_id'
    when 'inbox_summary' then 'inbox_id'
    when 'team_summary' then 'team_id'
    end
  end

  def known_custom_attribute_key?(attr_key, model)
    @account.custom_attribute_definitions.exists?(attribute_key: attr_key, attribute_model: model)
  end

  # Always Ruby: JSON CA values may be locale strings ("1000,00") that break PG ::float.
  def aggregate_custom_attr_by_sql_dimension(dimension, attr_key, op, since_time, until_time, contact_attr:, filter_op: nil, filter_value: nil)
    aggregate_custom_attr_in_ruby(
      dimension, attr_key, op, since_time, until_time,
      contact_attr: contact_attr, filter_op: filter_op, filter_value: filter_value
    )
  end

  def aggregate_custom_attr_in_ruby(dimension, attr_key, op, since_time, until_time, contact_attr:, filter_op: nil, filter_value: nil)
    scope = filtered_conversations_scope(since_time, until_time)
    # Agent summary keeps unassigned (nil assignee → UNASSIGNED_AGENT_ID); other dims skip nil.
    scope = scope.where.not(dimension => nil) unless dimension.to_s == 'assignee_id'

    buckets = Hash.new { |h, k| h[k] = [] }
    seen_contacts = Hash.new { |h, k| h[k] = {} }

    # ponytail: full range scan (batched). Old reorder(:id).limit(2k) biased early IDs.
    each_conversation_in_batches(scope, includes: [:contact]) do |conversation|
      dim_id = conversation.public_send(dimension)
      dim_id = UNASSIGNED_AGENT_ID if dimension.to_s == 'assignee_id' && dim_id.blank?
      next if dim_id.blank?

      if contact_attr
        contact = conversation.contact
        next if contact.blank? || seen_contacts[dim_id][contact.id]

        seen_contacts[dim_id][contact.id] = true
        val = contact.custom_attributes&.[](attr_key)
      else
        val = conversation.custom_attributes&.[](attr_key)
      end
      next if custom_attr_blank?(val)
      next unless custom_attr_matches_filter?(val, filter_op, filter_value)

      if op == 'count'
        buckets[dim_id] << 1
      else
        num = CustomAttributes::NumericParser.parse(val)
        buckets[dim_id] << num if num
      end
    end

    buckets.transform_values do |values|
      result = aggregate_numeric_values(values, op)
      result.is_a?(Float) ? result.round(2) : result
    end
  end

  def aggregate_custom_attr_by_label(attr_key, op, since_time, until_time, contact_attr:, filter_op: nil, filter_value: nil)
    labels = @account.labels.index_by(&:title)
    return {} if labels.empty?

    buckets = Hash.new { |h, k| h[k] = [] }
    seen_contacts = Hash.new { |h, k| h[k] = {} }

    each_conversation_in_batches(
      filtered_conversations_scope(since_time, until_time),
      includes: [:contact]
    ) do |conversation|
      label_titles = conversation.cached_label_list.to_s.split(',').map(&:strip).reject(&:blank?)
      next if label_titles.empty?

      if contact_attr
        contact = conversation.contact
        next if contact.blank?

        val = contact.custom_attributes&.[](attr_key)
        next if custom_attr_blank?(val)
        next unless custom_attr_matches_filter?(val, filter_op, filter_value)

        label_titles.each do |title|
          label = labels[title]
          next if label.blank? || seen_contacts[label.id][contact.id]

          seen_contacts[label.id][contact.id] = true
          if op == 'count'
            buckets[label.id] << 1
          else
            num = CustomAttributes::NumericParser.parse(val)
            buckets[label.id] << num if num
          end
        end
      else
        val = conversation.custom_attributes&.[](attr_key)
        next if custom_attr_blank?(val)
        next unless custom_attr_matches_filter?(val, filter_op, filter_value)

        label_titles.each do |title|
          label = labels[title]
          next if label.blank?

          if op == 'count'
            buckets[label.id] << 1
          else
            num = CustomAttributes::NumericParser.parse(val)
            buckets[label.id] << num if num
          end
        end
      end
    end

    buckets.transform_values do |values|
      result = aggregate_numeric_values(values, op)
      result.is_a?(Float) ? result.round(2) : result
    end
  end

  def custom_attr_blank?(val)
    val.nil? || val == '' || (val.is_a?(Array) && val.empty?)
  end

  # After non-blank check: optional equal_to match (case-insensitive, NFC, list-aware).
  def custom_attr_matches_filter?(val, filter_op, filter_value)
    return true if filter_op.blank?

    case filter_op.to_s
    when MEASURE_FILTER_EQ
      needle = normalize_ca_compare(filter_value)
      Array.wrap(val).any? { |item| normalize_ca_compare(item) == needle }
    else
      true
    end
  end

  def normalize_ca_compare(value)
    value.to_s.unicode_normalize(:nfc).downcase.strip
  end

  def report_builder(widget, since_time, until_time, metric: nil, group_by: 'day')
    scope_type = (widget[:scope_type].presence || 'account').to_sym
    params = {
      type: scope_type,
      id: widget[:scope_id],
      since: since_time.to_i.to_s,
      until: (until_time.to_i + 1).to_s,
      business_hours: @panel.business_hours,
      timezone_offset: @timezone_offset,
      group_by: group_by
    }
    params[:metric] = metric if metric.present?
    V2::ReportBuilder.new(@account, params)
  end

  def summary_builder(klass, since_time, until_time, type: nil)
    params = {
      since: since_time.to_i.to_s,
      until: (until_time.to_i + 1).to_s,
      business_hours: @panel.business_hours
    }
    params[:type] = type if type.present?
    klass.new(account: @account, params: params).build
  end

  def filtered_or_builder_summary(klass, dimension, since_time, until_time, type: nil)
    if conversation_filters? || contact_filters? || panel_date_attribute_key.present?
      filtered_dimension_summary(dimension, since_time, until_time)
    else
      event_dimension = dimension == :inbox_id ? 'reporting_events.inbox_id' : nil
      resolved_counts = dimension_resolution_counts(dimension, since_time, until_time, event_dimension: event_dimension)
      summary_builder(klass, since_time, until_time, type: type).map do |row|
        row.merge(resolved_conversations_count: resolved_counts.fetch(row[:id], 0))
      end
    end
  end

  def filtered_or_label_summary(since_time, until_time)
    if conversation_filters? || contact_filters? || panel_date_attribute_key.present?
      filtered_label_summary(since_time, until_time)
    else
      resolved_counts = label_resolution_counts(since_time, until_time)
      summary_builder(V2::Reports::LabelSummaryBuilder, since_time, until_time).map do |row|
        row.merge(resolved_conversations_count: resolved_counts.fetch(row[:name], 0))
      end
    end
  end

  def filtered_dimension_summary(dimension, since_time, until_time)
    conv_ids = filtered_conversation_ids_subquery(since_time, until_time)
    conversations_count = Conversation.where(id: conv_ids).group(dimension).count
    events = ReportingEvent.where(account_id: @account.id, conversation_id: conv_ids, created_at: since_time..until_time)
    event_dimension = dimension == :assignee_id ? 'reporting_events.user_id' : "conversations.#{dimension}"
    resolved_count = dimension_resolution_counts(dimension, since_time, until_time)
    avg_map = lambda do |event_name|
      events.where(name: event_name).joins(:conversation).group(event_dimension)
            .average(average_value_key)
    end

    first_response = avg_map.call('first_response')
    resolution_time = avg_map.call('conversation_resolved')
    reply_time = avg_map.call('reply_time')
    ids = (conversations_count.keys | resolved_count.keys | first_response.keys | resolution_time.keys | reply_time.keys).compact
    ids.map do |id|
      {
        id: id,
        conversations_count: conversations_count[id] || 0,
        resolved_conversations_count: resolved_count[id] || 0,
        avg_first_response_time: first_response[id],
        avg_resolution_time: resolution_time[id],
        avg_reply_time: reply_time[id]
      }
    end
  end

  def filtered_label_summary(since_time, until_time)
    labels = @account.labels.to_a
    return [] if labels.empty?

    conv_ids = filtered_conversation_ids_subquery(since_time, until_time)
    conversation_counts = ActsAsTaggableOn::Tagging
                          .joins('INNER JOIN conversations ON taggings.taggable_id = conversations.id')
                          .joins('INNER JOIN tags ON taggings.tag_id = tags.id')
                          .where(taggable_type: 'Conversation', context: 'labels', taggable_id: conv_ids)
                          .group('tags.name')
                          .count

    events = ReportingEvent
             .joins(conversation: { taggings: :tag })
             .where(
               account_id: @account.id,
               conversation_id: conv_ids,
               created_at: since_time..until_time,
               taggings: { taggable_type: 'Conversation', context: 'labels' }
             )

    resolved_counts = label_resolution_counts(since_time, until_time)
    avg_for = lambda do |event_name|
      events.where(name: event_name).group('tags.name').average(average_value_key)
    end

    labels.map do |label|
      {
        id: label.id,
        name: label.title,
        conversations_count: conversation_counts[label.title] || 0,
        resolved_conversations_count: resolved_counts[label.title] || 0,
        avg_resolution_time: avg_for.call('conversation_resolved')[label.title],
        avg_first_response_time: avg_for.call('first_response')[label.title],
        avg_reply_time: avg_for.call('reply_time')[label.title]
      }
    end
  end

  def enrich_named_rows(rows, name_map:, extra_maps: {})
    rows = Array(rows).map { |row| row.with_indifferent_access }
    total_conversations = rows.sum { |row| row[:conversations_count].to_i }
    ranked = rows.sort_by { |row| -row[:conversations_count].to_i }

    ranked.map.with_index(1) do |row, rank|
      payload = {
        rank: rank,
        id: row[:id],
        name: row[:name].presence || name_map[row[:id]].presence || "##{row[:id]}",
        conversations_count: row[:conversations_count] || 0,
        resolved_conversations_count: row[:resolved_conversations_count] || 0,
        avg_first_response_time: row[:avg_first_response_time],
        avg_resolution_time: row[:avg_resolution_time],
        avg_reply_time: row[:avg_reply_time],
        share_percent: share_percent(row[:conversations_count], total_conversations)
      }
      extra_maps.each do |key, map|
        value = map[row[:id]]
        key_s = key.to_s
        payload[key] =
          if value.nil? && (key_s.end_with?('_count') || summary_ca_column?(key_s))
            0
          else
            value
          end
      end
      payload
    end
  end

  def agent_extra_column_maps(since_time, until_time)
    conv_ids = (conversation_filters? || contact_filters? || panel_date_attribute_key.present?) ? filtered_conversation_ids_subquery(since_time, until_time) : nil
    csat_scope = @account.csat_survey_responses.where(created_at: since_time..until_time).where.not(assigned_agent_id: nil)
    csat_scope = csat_scope.where(conversation_id: conv_ids) if conv_ids
    csat_avg = csat_scope.group(:assigned_agent_id).average(:rating)

    messages = @account.messages.where(created_at: since_time..until_time).unscope(:order)
    messages = messages.where(conversation_id: conv_ids) if conv_ids

    outgoing = messages.outgoing.where(sender_type: 'User').where.not(sender_id: nil).group(:sender_id).count
    incoming = messages.incoming.joins(:conversation).where.not(conversations: { assignee_id: nil })
                       .group('conversations.assignee_id').count

    {
      csat_avg: csat_avg.transform_values { |v| v&.to_f&.round(2) },
      outgoing_messages_count: outgoing,
      incoming_messages_count: incoming
    }
  end

  def share_percent(count, total)
    return 0.0 if total.to_i.zero?

    (count.to_f / total * 100).round(1)
  end

  def agent_name_map
    map = @account.account_users.includes(:user).each_with_object({}) do |account_user, memo|
      user = account_user.user
      next if user.blank?

      memo[user.id] = user.available_name.presence || user.name.presence || user.email
    end
    map[UNASSIGNED_AGENT_ID] = I18n.t('reports.panels.unassigned_agent')
    map
  end

  # Append synthetic row so ∑ Conversaciones (tabla) can match the account KPI.
  def with_unassigned_agent_row(rows, since_time, until_time)
    list = Array(rows).map { |row| row.with_indifferent_access }
    list = list.reject { |row| row[:id].nil? || row[:id] == UNASSIGNED_AGENT_ID }
    count, resolved = unassigned_agent_conversation_stats(since_time, until_time)
    events = @account.reporting_events.where(user_id: nil, created_at: since_time..until_time)
    if conversation_filters? || contact_filters? || panel_date_attribute_key.present?
      events = events.where(conversation_id: filtered_conversation_ids_subquery(since_time, until_time))
    end
    list + [{
      id: UNASSIGNED_AGENT_ID,
      conversations_count: count,
      resolved_conversations_count: resolved,
      avg_first_response_time: events.where(name: 'first_response').average(average_value_key),
      avg_resolution_time: events.where(name: 'conversation_resolved').average(average_value_key),
      avg_reply_time: events.where(name: 'reply_time').average(average_value_key)
    }]
  end

  def unassigned_agent_conversation_stats(since_time, until_time)
    unassigned = filtered_conversations_scope(since_time, until_time).where(assignee_id: nil)
    resolved = resolution_events_scope(since_time, until_time).where(user_id: nil).distinct.count(:conversation_id)
    [unassigned.count, resolved]
  end

  def filtered_conversation_rows(since_time, until_time, columns = [])
    scope = filtered_conversations_scope(since_time, until_time)
             .includes(:inbox, :assignee, :contact)
             .limit(SavedReportPanel::DETAIL_CONVERSATIONS_LIMIT)

    scope.map do |conversation|
      row = {
        id: conversation.display_id,
        contact_name: conversation.contact&.name.presence || "##{conversation.contact_id}",
        status: conversation.status,
        priority: conversation.priority,
        labels: conversation.cached_label_list.to_s,
        inbox: conversation.inbox&.name,
        assignee: conversation.assignee&.available_name.presence || conversation.assignee&.name,
        created_at: conversation.created_at.to_i,
        last_activity_at: conversation.last_activity_at.to_i
      }
      merge_custom_attribute_columns(row, conversation.custom_attributes, columns)
    end
  end

  # Distinct contacts from filtered conversations in the date range (attended in period).
  def filtered_contact_rows(since_time, until_time, columns = [])
    limit = SavedReportPanel::DETAIL_CONTACTS_LIMIT
    # ponytail: walk newest matching convos until `limit` unique contacts; scan ceiling limit*20
    scope = filtered_conversations_scope(since_time, until_time)
             .includes(:inbox, :assignee, contact: :assigned_agent)
             .reorder(created_at: :desc)
             .limit(limit * 20)

    matched = []
    seen = {}
    scope.each do |conversation|
      contact_id = conversation.contact_id
      next if contact_id.blank? || seen[contact_id]

      seen[contact_id] = true
      matched << conversation
      break if matched.size >= limit
    end

    contact_ids = matched.map(&:contact_id)
    conversation_counts = Conversation.where(id: filtered_conversation_ids_subquery(since_time, until_time))
                                      .where(contact_id: contact_ids)
                                      .group(:contact_id)
                                      .count

    matched.map do |conversation|
      contact_row_from_conversation(conversation, conversation_counts, columns)
    end
  end

  def contact_row_from_conversation(conversation, conversation_counts = {}, columns = [])
    contact = conversation.contact
    assignee = contact&.assigned_agent
    row = {
      id: contact&.id,
      name: contact&.name.presence || "##{contact&.id}",
      phone_number: contact&.phone_number,
      email: contact&.email,
      document_number: contact&.document_number,
      labels: Array(contact&.label_list).join(', '),
      conversations_count: conversation_counts[contact&.id] || 1,
      assignee: assignee&.available_name.presence || assignee&.name.presence ||
                conversation.assignee&.available_name.presence || conversation.assignee&.name,
      inbox: conversation.inbox&.name,
      created_at: contact&.created_at&.to_i || conversation.created_at.to_i,
      last_activity_at: contact&.last_activity_at&.to_i || conversation.last_activity_at.to_i
    }
    merge_custom_attribute_columns(row, contact&.custom_attributes, columns)
  end

  def merge_custom_attribute_columns(row, custom_attributes, columns)
    attrs = (custom_attributes || {}).with_indifferent_access
    Array(columns).each do |col|
      col = col.to_s
      next unless col.start_with?(CA_COLUMN_PREFIX)

      key = col.delete_prefix(CA_COLUMN_PREFIX)
      row[col] = attrs[key]
    end
    row
  end

  def custom_attribute_type_map_for(table_kind, columns = [])
    models = attribute_models_for_table(table_kind, columns)
    return {} if models.blank?

    defs_by_key = @account.custom_attribute_definitions.where(attribute_model: models).index_by(&:attribute_key)
    map = {}
    defs_by_key.each do |key, definition|
      type = definition.attribute_display_type
      map[key] = type
      if definition.contact_attribute?
        map["#{CONTACT_CA_COLUMN_PREFIX}#{key}"] = type if SUMMARY_TABLE_KINDS.include?(table_kind.to_s)
      elsif definition.conversation_attribute?
        map["#{CA_COLUMN_PREFIX}#{key}"] = type
      end
    end

    # Measure columns (ca:ventas__sum) inherit the base attribute type for currency/$ formatting.
    Array(columns).map(&:to_s).each do |col|
      next unless summary_ca_column?(col)

      attr_key, op, contact, _filter_op, _filter_value = parse_summary_ca_column(col)
      next if op.blank?

      definition = defs_by_key[attr_key]
      next if definition.blank?
      next if contact && !definition.contact_attribute?
      next if !contact && !definition.conversation_attribute?

      map[col] = definition.attribute_display_type
    end
    map
  end

  def attribute_models_for_table(table_kind, columns)
    case table_kind.to_s
    when 'conversations'
      [:conversation_attribute]
    when 'contacts'
      [:contact_attribute]
    when *SUMMARY_TABLE_KINDS
      cols = Array(columns).map(&:to_s)
      selected = []
      selected << :conversation_attribute if cols.any? { |c| c.start_with?(CA_COLUMN_PREFIX) }
      selected << :contact_attribute if cols.any? { |c| c.start_with?(CONTACT_CA_COLUMN_PREFIX) }
      selected.presence || %i[conversation_attribute contact_attribute]
    else
      []
    end
  end

  def build_table_totals(rows, columns, total_count, attribute_types, column_aggregations = {})
    # Only columns with an explicit aggregation in widget JSON get a footer value.
    configured = column_aggregations.presence || {}
    column_results = {}

    configured.each do |col, op|
      col = col.to_s
      op = op.to_s
      next if op.blank?
      next unless Array(columns).map(&:to_s).include?(col)

      values = Array(rows).map { |row| row.with_indifferent_access[col] }
      column_results[col] = {
        op: op,
        value: aggregate_column_values(values, op)
      }
    end

    # columns: { key => number } for FE/export footer; ops: { key => op } for labels
    {
      count: total_count,
      columns: column_results.transform_values { |entry| entry[:value] },
      ops: column_results.transform_values { |entry| entry[:op] }
    }
  end

  def aggregate_column_values(values, op)
    return Array(values).count { |v| !v.nil? && v != '' } if op == 'count'

    nums = Array(values).filter_map { |value| CustomAttributes::NumericParser.parse(value) }
    return nil if nums.empty?

    case op
    when 'sum' then nums.sum
    when 'avg' then nums.sum.to_f / nums.size
    when 'min' then nums.min
    when 'max' then nums.max
    else nums.sum
    end
  end

  # Locale-safe parse; nil when unparseable (display/legacy callers may coerce).
  def numeric_table_cell(value)
    CustomAttributes::NumericParser.parse(value) || 0
  end

  def unique_contacts_count(since_time, until_time)
    Conversation.where(id: filtered_conversation_ids_subquery(since_time, until_time))
                .distinct
                .count(:contact_id)
  end

  def filtered_metric_value(metric, since_time, until_time)
    conv_ids = filtered_conversation_ids_subquery(since_time, until_time)

    case metric
    when 'conversations_count'
      Conversation.where(id: conv_ids).count
    when 'incoming_messages_count'
      filtered_messages_scope(conv_ids, since_time, until_time).incoming.count
    when 'outgoing_messages_count'
      filtered_messages_scope(conv_ids, since_time, until_time).outgoing.count
    when 'avg_first_response_time'
      filtered_events_scope(conv_ids, since_time, until_time, 'first_response').average(average_value_key) || 0
    when 'avg_resolution_time'
      filtered_events_scope(conv_ids, since_time, until_time, 'conversation_resolved').average(average_value_key) || 0
    when 'reply_time'
      filtered_events_scope(conv_ids, since_time, until_time, 'reply_time').average(average_value_key) || 0
    else
      nil
    end
  end

  def filtered_chart_points(metric, since_time, until_time, group_by)
    conv_ids = filtered_conversation_ids_subquery(since_time, until_time)
    range = since_time..until_time
    timezone = timezone_name

    series =
      case metric
      when 'conversations_count'
        Conversation.where(id: conv_ids).group_by_period(
          group_by, :created_at, default_value: 0, range: range, permit: %w[day week month year hour], time_zone: timezone
        ).count
      when 'incoming_messages_count'
        filtered_messages_scope(conv_ids, since_time, until_time).incoming.group_by_period(
          group_by, :created_at, default_value: 0, range: range, permit: %w[day week month year hour], time_zone: timezone
        ).count
      when 'outgoing_messages_count'
        filtered_messages_scope(conv_ids, since_time, until_time).outgoing.group_by_period(
          group_by, :created_at, default_value: 0, range: range, permit: %w[day week month year hour], time_zone: timezone
        ).count
      when 'avg_first_response_time', 'avg_resolution_time', 'reply_time'
        event_name = { 'avg_first_response_time' => 'first_response', 'avg_resolution_time' => 'conversation_resolved',
                       'reply_time' => 'reply_time' }[metric]
        averages = filtered_events_scope(conv_ids, since_time, until_time, event_name).group_by_period(
          group_by, :created_at, default_value: 0, range: range, permit: %w[day week month year hour], time_zone: timezone
        ).average(average_value_key)
        counts = filtered_events_scope(conv_ids, since_time, until_time, event_name).group_by_period(
          group_by, :created_at, default_value: 0, range: range, permit: %w[day week month year hour], time_zone: timezone
        ).count
        return averages.map do |period, value|
          { value: value, timestamp: period.in_time_zone(timezone).to_i, count: counts[period] }
        end
      else
        {}
      end

    series.map { |period, value| { value: value, timestamp: period.in_time_zone(timezone).to_i } }
  end

  def filtered_messages_scope(conv_ids, since_time, until_time)
    @account.messages.where(conversation_id: conv_ids, created_at: since_time..until_time).unscope(:order)
  end

  def filtered_events_scope(conv_ids, since_time, until_time, event_name)
    ReportingEvent.where(
      account_id: @account.id,
      conversation_id: conv_ids,
      created_at: since_time..until_time,
      name: event_name
    )
  end

  def resolution_events_scope(since_time, until_time)
    conv_ids = conversations_matching_filters_without_date.unscope(:order).reselect(:id)
    filtered_events_scope(conv_ids, since_time, until_time, 'conversation_resolved')
  end

  def widget_resolution_events_scope(widget, since_time, until_time)
    events = resolution_events_scope(since_time, until_time)
    return events if conversation_filters? || contact_filters? || panel_date_attribute_key.present?

    events.merge(resolution_reporting_scope(widget).reporting_events)
  end

  def resolution_reporting_scope(widget)
    case widget[:scope_type].to_s
    when 'account', '' then @account
    when 'agent' then @account.users.find(widget[:scope_id])
    when 'inbox' then @account.inboxes.find(widget[:scope_id])
    when 'team' then @account.teams.find(widget[:scope_id])
    when 'label' then @account.labels.find(widget[:scope_id])
    end
  end

  def resolution_chart_points(widget, since_time, until_time, group_by)
    timezone = timezone_name
    widget_resolution_events_scope(widget, since_time, until_time).group_by_period(
      group_by, :created_at,
      default_value: 0,
      range: since_time..until_time,
      permit: %w[day week month year hour],
      time_zone: timezone
    ).distinct.count(:conversation_id).map do |period, count|
      { value: count, timestamp: period.in_time_zone(timezone).to_i }
    end
  end

  def dimension_resolution_counts(dimension, since_time, until_time, event_dimension: nil)
    event_dimension ||= dimension == :assignee_id ? 'reporting_events.user_id' : "conversations.#{dimension}"
    resolution_events_scope(since_time, until_time)
      .joins(:conversation)
      .group(event_dimension)
      .distinct.count('reporting_events.conversation_id')
  end

  def label_resolution_counts(since_time, until_time)
    resolution_events_scope(since_time, until_time)
      .joins(conversation: { taggings: :tag })
      .where(taggings: { taggable_type: 'Conversation', context: 'labels' })
      .group('tags.name').distinct.count('reporting_events.conversation_id')
  end

  def filtered_contacts_count(since_time, until_time)
    scope =
      if contact_filters?
        Contacts::FilterService.new(
          @account,
          @user,
          { payload: contact_filter_payload }
        ).perform[:contacts]
      else
        @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
      end

    scope.where(created_at: since_time..until_time).count
  end

  def filtered_conversations_scope(since_time, until_time)
    scope = conversations_matching_filters_without_date

    date_key = panel_date_attribute_key
    if date_key.present?
      ids = conversation_ids_for_attribute_date_range(since_time, until_time, date_key)
      return scope.where(id: ids)
    end

    scope.where(created_at: since_time..until_time)
  end

  def filtered_conversation_ids_subquery(since_time, until_time)
    filtered_conversations_scope(since_time, until_time).reselect(:id)
  end

  def filtered_contact_ids
    @filtered_contact_ids ||= Contacts::FilterService.new(
      @account,
      @user,
      { payload: contact_filter_payload }
    ).perform[:contacts].unscope(:limit, :offset).reselect(:id)
  end

  def conversation_filters?
    conversation_filter_payload.present?
  end

  def contact_filters?
    contact_filter_payload.present?
  end

  def conversation_filter_payload
    @conversation_filter_payload ||= split_filters[:conversation]
  end

  def contact_filter_payload
    @contact_filter_payload ||= split_filters[:contact]
  end

  def split_filters
    @split_filters ||= begin
      conversation = []
      contact = []
      Array(@panel.filters).each do |raw|
        filter = raw.with_indifferent_access.deep_dup
        if contact_filter_condition?(filter)
          contact << filter
        else
          conversation << filter
        end
      end
      # Drop trailing query_operator on last condition of each group
      [conversation, contact].each do |list|
        list.last[:query_operator] = nil if list.present?
      end
      { conversation: conversation, contact: contact }
    end
  end

  def contact_filter_condition?(filter)
    SavedReportPanel::CONTACT_FILTER_TYPES.include?(filter[:custom_attribute_type].to_s)
  end

  def average_value_key
    ActiveModel::Type::Boolean.new.cast(@panel.business_hours) ? :value_in_business_hours : :value
  end

  def timezone_name
    ActiveSupport::TimeZone[@timezone_offset]&.name || Time.zone.name
  end
end
