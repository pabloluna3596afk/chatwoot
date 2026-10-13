class Reports::PanelRunnerService
  # ponytail: statement_timeout caps expensive panel runs; raise if panels need longer windows
  STATEMENT_TIMEOUT_MS = 15_000
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
      # Full range scan (batched) — same universe as pivot measures.
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

  def custom_attr_blank?(value)
    value.nil? || value == '' || value == []
  end

  def build_table_widget(widget, since_time, until_time)
    return build_detail_table_widget(widget, since_time, until_time) unless widget[:table_kind] == 'pivot'

    Reports::PanelPivotService.new(
      widget: widget, account: @account, timezone_offset: @timezone_offset,
      conversations: filtered_conversations_scope(since_time, until_time),
      resolutions: resolution_events_scope(since_time, until_time)
    ).perform
  end

  def build_detail_table_widget(widget, since_time, until_time)
    table_kind = widget.fetch(:table_kind)
    columns = Array(widget[:columns])
    rows = detail_table_rows(table_kind, columns, since_time, until_time)
    total_count = detail_table_count(table_kind, since_time, until_time)
    attribute_types = custom_attribute_type_map_for(table_kind)
    resolved_columns = columns.presence || rows.first&.keys&.map(&:to_s) || []
    totals = build_table_totals(rows, total_count, widget.fetch(:column_aggregations, {}))
    widget.slice(:id, :type, :title, :table_kind).merge(
      columns: resolved_columns, rows: rows, total_count: total_count,
      truncated: rows.size < total_count, attribute_types: attribute_types, totals: totals
    )
  end

  def detail_table_rows(table_kind, columns, since_time, until_time)
    return filtered_contact_rows(since_time, until_time, columns) if table_kind == 'contacts'

    filtered_conversation_rows(since_time, until_time, columns)
  end

  def detail_table_count(table_kind, since_time, until_time)
    return unique_contacts_count(since_time, until_time) if table_kind == 'contacts'

    filtered_conversations_scope(since_time, until_time).count
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

  def custom_attribute_type_map_for(table_kind)
    model = table_kind == 'contacts' ? :contact_attribute : :conversation_attribute
    @account.custom_attribute_definitions.where(attribute_model: model).each_with_object({}) do |definition, map|
      key = definition.attribute_key
      map[key] = definition.attribute_display_type
      map["#{CA_COLUMN_PREFIX}#{key}"] = definition.attribute_display_type
    end
  end

  def build_table_totals(rows, total_count, column_aggregations)
    values = column_aggregations.to_h do |column, op|
      cells = rows.map { |row| row.with_indifferent_access[column] }
      [column, aggregate_column_values(cells, op)]
    end
    { count: total_count, columns: values, ops: column_aggregations }
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
