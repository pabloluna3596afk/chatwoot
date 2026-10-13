class Reports::PanelPivotService
  IDENTITY_COLUMNS = %w[id name rank].freeze

  def initialize(widget:, account:, conversations:, resolutions:, timezone_offset:)
    @widget = widget
    @account = account
    @conversations = conversations
    @resolutions = resolutions
    @pivot = widget.fetch(:pivot)
    @measures = (widget.fetch(:columns) - IDENTITY_COLUMNS).map { |key| Reports::PanelPivotMeasure.new(key) }
    @dimension = Reports::PanelPivotDimension.new(account: account, pivot: @pivot, timezone_offset: timezone_offset)
  end

  def perform
    scan
    builder = Reports::PanelPivotRows.new(widget: @widget, measures: @measures, buckets: @buckets, values: @values, names: @dimension.names)
    population = @buckets.rows.map { |id, cells| builder.build(id, cells) }
    totals = build_totals(population)
    selected = builder.select(population)
    Reports::PanelPivotPercentages.new(displays: @widget.fetch(:measure_display, {}), measures: @measures, values: @values)
                                  .apply(population, selected, totals)
    rows = builder.order(selected)
    rows.each { |row| row.slice!(*(columns + %w[id name rank is_others])) }
    result(rows, population.size, totals)
  end

  private

  def scan
    @buckets = Reports::PanelPivotBuckets.new(measures: @measures, dimension: @dimension, selected_values: @pivot.fetch(:column_values, []))
    events = @resolutions
    events = events.where(conversation_id: @conversations.reselect(:id)) if @pivot[:row_attribute] == 'created_at'
    @buckets.scan(@conversations, events)
    @values = @dimension.column_values(@buckets.values)
  end

  def columns
    identity = @widget[:columns].select { |column| IDENTITY_COLUMNS.include?(column) }
    crossed = @values.flat_map { |value| @measures.map { |measure| measure.column_key(value) } }
    identity + crossed + (show_row_totals? ? @measures.map(&:key) : [])
  end

  def show_row_totals?
    @pivot[:column_attribute].blank? || @pivot.fetch(:show_row_totals, true)
  end

  def build_totals(population)
    totals = { count: population.size, columns: {}, ops: {} }
    column_values = [nil] + @values
    @measures.each do |measure|
      column_values.each do |value|
        column = value.nil? ? measure.key : measure.column_key(value)
        next unless columns.include?(column)

        op = @widget.fetch(:column_aggregations, {}).fetch(measure.key, measure.footer_op)
        totals[:columns][column] = footer_total(measure, value, column, op, population)
        totals[:ops][column] = op
      end
    end
    totals
  end

  def footer_total(measure, value, column, operation, population)
    return measure_total(measure, value) if operation == measure.footer_op

    values = population.filter_map { |row| row[column] }
    return values.size if operation == 'count'
    return values.sum if operation == 'sum'
    return nil if values.empty?

    total = operation == 'avg' ? values.sum.to_f / values.size : values.public_send(operation)
    total.round(2)
  end

  def measure_total(measure, value)
    samples = @buckets.rows.values.flat_map do |cells|
      selected = value.nil? ? cells.values : [cells.fetch(value, {})]
      selected.map { |cell| cell.fetch(measure.key, {}) }
    end
    measure.combine(samples)
  end

  def attribute_types
    definitions = @account.custom_attribute_definitions.index_by { |definition| [definition.attribute_key, definition.contact_attribute?] }
    @measures.each_with_object({}) do |measure, types|
      definition = definitions[[measure.attribute_key, measure.contact? == true]]
      next unless definition

      types[measure.key] = definition.attribute_display_type
      @values.each { |value| types[measure.column_key(value)] = definition.attribute_display_type }
    end
  end

  def result(rows, count, totals)
    {
      id: @widget[:id], type: 'table', title: @widget[:title], table_kind: @widget[:table_kind],
      columns: columns, rows: rows, total_count: count, attribute_types: attribute_types, totals: totals,
      pivot: @pivot.merge(column_values: @values, measures: @measures.map(&:key), show_row_totals: show_row_totals?)
    }
  end
end
