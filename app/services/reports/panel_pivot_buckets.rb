class Reports::PanelPivotBuckets
  MAX_ROWS = 1_000
  MAX_BUCKETS = 12_000

  attr_reader :rows, :values

  def initialize(measures:, dimension:, selected_values:)
    @measures = measures
    @dimension = dimension
    @selected_values = selected_values
    @rows = {}
    @values = []
    @bucket_count = 0
  end

  def scan(conversations, resolutions)
    conversations.unscope(:order).includes(:contact).find_each(batch_size: 250) { |conversation| add_conversation(conversation) }
    return unless @measures.any? { |measure| measure.key == 'resolved_conversations_count' }

    resolutions.includes(conversation: :contact).find_each { |event| add_resolution(event) }
  end

  def merged(ids)
    values = ids.flat_map { |id| @rows.fetch(id).keys }.uniq
    values.index_with do |value|
      @measures.to_h do |measure|
        accumulators = ids.map { |id| @rows.fetch(id).fetch(value, {}).fetch(measure.key, {}) }
        [measure.key, measure.merge(accumulators)]
      end
    end
  end

  private

  def add_conversation(conversation)
    value = @dimension.column_value(conversation)
    return if @selected_values.present? && @selected_values.exclude?(value)

    @dimension.ids(conversation).each do |id|
      cell = cell_for(id, value)
      @measures.each { |measure| measure.accumulate(cell.fetch(measure.key), conversation) }
    end
  end

  def add_resolution(event)
    value = @dimension.column_value(event.conversation)
    return if @selected_values.present? && @selected_values.exclude?(value)

    @dimension.resolution_ids(event).each do |id|
      cell_for(id, value).fetch('resolved_conversations_count')[event.conversation_id] = 1
    end
  end

  def cell_for(id, value)
    allocate_row(id) unless @rows.key?(id)
    cells = @rows.fetch(id)
    return cells[value] if cells.key?(value)

    @bucket_count += 1
    check_limit!(@bucket_count > MAX_BUCKETS, 'bucket')
    @values << value unless @values.include?(value)
    cells[value] = empty_cell
  end

  def allocate_row(id)
    check_limit!(@rows.size >= MAX_ROWS, 'row')
    @rows[id] = {}
  end

  def empty_cell
    @measures.to_h { |measure| [measure.key, measure.empty] }
  end

  def check_limit!(exceeded, kind)
    return unless exceeded

    raise CustomExceptions::InvalidPanelPivot, "pivot_#{kind}_limit_exceeded: reduce the date range or filters"
  end
end
