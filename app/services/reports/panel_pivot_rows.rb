class Reports::PanelPivotRows
  def initialize(widget:, measures:, buckets:, values:, names:)
    @widget = widget
    @measures = measures
    @buckets = buckets
    @values = values
    @names = names
  end

  def build(id, cells)
    row = { 'id' => id, 'name' => @names.fetch(id, "##{id}") }
    @measures.each do |measure|
      row[measure.key] = measure.combine(cells.values.map { |cell| cell.fetch(measure.key) })
      @values.each do |value|
        sample = cells.fetch(value, {}).fetch(measure.key, {})
        row[measure.column_key(value)] = measure.combine([sample])
      end
    end
    row
  end

  def select(rows)
    top = @widget[:top_n]
    return rows if top.nil? || top[:limit].nil?

    selected = sort(rows, top[:column], 'desc').first(top[:limit])
    excluded = rows - selected
    return selected unless top[:include_others] && excluded.any?

    others = build('__others__', @buckets.merged(excluded.pluck('id')))
    others['is_others'] = true
    selected + [others]
  end

  def order(rows)
    date_rows = @widget.dig(:pivot, :row_attribute) == 'created_at'
    default_column = date_rows ? 'name' : default_measure
    options = @widget[:sort] || { column: default_column, direction: date_rows ? 'asc' : 'desc' }
    regular, others = rows.partition { |row| !row['is_others'] }
    (sort(regular, options[:column], options[:direction]) + others).each_with_index do |row, index|
      row['rank'] = index + 1
    end
  end

  private

  def default_measure
    keys = @measures.map(&:key)
    keys.include?('conversations_count') ? 'conversations_count' : keys.first
  end

  def sort(rows, column, direction)
    rows.sort do |left, right|
      comparison = compare(left[column], right[column], direction)
      comparison.zero? ? left['id'].to_s <=> right['id'].to_s : comparison
    end
  end

  # Nulls always go last, whatever the direction.
  def nil_order(left, right)
    return 0 if left.nil? == right.nil?

    left.nil? ? 1 : -1
  end

  def compare(left, right, direction)
    return nil_order(left, right) if left.nil? || right.nil?

    value = left.is_a?(Numeric) && right.is_a?(Numeric) ? left <=> right : left.to_s <=> right.to_s
    direction == 'desc' ? -value : value
  end
end
