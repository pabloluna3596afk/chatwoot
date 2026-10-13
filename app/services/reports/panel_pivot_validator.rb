class Reports::PanelPivotValidator
  PIVOT_KEYS = %w[row_attribute row_granularity column_attribute column_values show_row_totals].freeze
  DISPLAYS = %w[value row_percent column_percent].freeze
  FORMAT_KEYS = %w[type currency_symbol decimals].freeze
  FORMAT_TYPES = %w[currency percent integer].freeze
  ATTRIBUTE = /\A(?:ca|contact_ca):[\p{L}\p{N}_.\-]+\z/

  def initialize(panel, widget, index)
    @panel = panel
    @widget = widget
    @index = index
    @columns = widget[:columns].is_a?(Array) ? widget[:columns] : []
    @measures = @columns - Reports::PanelPivotService::IDENTITY_COLUMNS
  end

  def validate
    pivot = @widget[:pivot]
    return error('invalid pivot') unless pivot.is_a?(Hash)

    @pivot = pivot
    error('invalid pivot keys') unless (pivot.keys - PIVOT_KEYS).empty?
    validate_rows
    validate_column_attribute
    validate_column_values
    validate_row_totals
    return unless validate_measures

    validate_sort if @widget.key?(:sort)
    validate_top if @widget.key?(:top_n)
    validate_map('measure_display') { |key, value| valid_display?(key, value) }
    validate_map('column_formats') { |_key, value| valid_format?(value) }
  end

  private

  def validate_rows
    row = @pivot[:row_attribute]
    valid = row.is_a?(String) && (%w[agent inbox team label created_at].include?(row) || row.match?(ATTRIBUTE))
    error('invalid pivot row_attribute') unless valid
    validate_granularity(row)
  end

  def validate_granularity(row)
    return unless @pivot.key?(:row_granularity)

    valid = row == 'created_at' && %w[day week month].include?(@pivot[:row_granularity])
    error('invalid pivot row_granularity') unless valid
  end

  def validate_column_attribute
    attr = @pivot[:column_attribute]
    return unless @pivot.key?(:column_attribute)
    return if attr.is_a?(String) && (attr.empty? || attr.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/))

    error('invalid pivot column_attribute')
  end

  def validate_column_values
    return unless @pivot.key?(:column_values)

    values = @pivot[:column_values]
    error('invalid pivot column_values') unless valid_column_values?(values)
    error('column_values require crossed columns') if values.present? && @pivot[:column_attribute].blank?
  end

  def valid_column_values?(values)
    values.is_a?(Array) && values.all?(String) && values.size <= 12 && values.uniq == values
  end

  def validate_row_totals
    return unless @pivot.key?(:show_row_totals)
    return if [true, false].include?(@pivot[:show_row_totals])

    error('invalid pivot show_row_totals')
  end

  def validate_measures
    unless valid_measure_columns?
      error('invalid pivot columns')
      return false
    end

    @measures.each do |key|
      next if Reports::PanelPivotMeasure::SYSTEM_KEYS.include?(key) || key.match?(Reports::PanelPivotMeasure::CUSTOM_KEY)

      error("invalid pivot measure: #{key}")
    end
    true
  end

  def valid_measure_columns?
    @widget[:columns].is_a?(Array) && @columns.all?(String) && @columns.uniq == @columns && @measures.any?
  end

  def valid_column?(column, allowed)
    return false unless column.is_a?(String)
    return true if allowed.include?(column)
    return false if @pivot[:column_attribute].blank?

    measure, value = column.split('__pv__', 2)
    allowed.include?(measure) && !value.nil?
  end

  def validate_sort
    sort = @widget[:sort]
    valid = sort.is_a?(Hash) && (sort.keys - %w[column direction]).empty? &&
            valid_column?(sort[:column], @columns) && %w[asc desc].include?(sort[:direction])
    error('invalid sort') unless valid
  end

  def validate_top
    top = @widget[:top_n]
    return error('invalid top_n') unless valid_top?(top)
    return unless top[:include_others] && @measures.any? { |key| key.start_with?('contact_ca:') }

    error('Others is unavailable for contact measures')
  end

  def valid_top?(top)
    top.is_a?(Hash) && (top.keys - %w[limit column include_others]).empty? &&
      top.key?(:limit) && valid_limit?(top[:limit]) && valid_column?(top[:column], @measures) &&
      [true, false].include?(top[:include_others])
  end

  def valid_limit?(limit)
    limit.nil? || (limit.is_a?(Integer) && [5, 10, 20].include?(limit))
  end

  def validate_map(option)
    return unless @widget.key?(option)

    map = @widget[option]
    return error("invalid #{option}") unless map.is_a?(Hash)

    map.each do |key, value|
      error("invalid #{option} measure: #{key}") unless @measures.include?(key) && yield(key, value)
    end
  end

  def valid_display?(key, value)
    DISPLAYS.include?(value) && (value == 'value' || Reports::PanelPivotMeasure.new(key).additive?)
  end

  def valid_format?(value)
    return false unless value.is_a?(Hash) && (value.keys - FORMAT_KEYS).empty? && FORMAT_TYPES.include?(value[:type])

    valid_symbol?(value) && valid_decimals?(value)
  end

  def valid_symbol?(value)
    !value.key?(:currency_symbol) || value[:currency_symbol].is_a?(String)
  end

  def valid_decimals?(value)
    !value.key?(:decimals) || (value[:decimals].is_a?(Integer) && (0..2).cover?(value[:decimals]))
  end

  def error(message)
    @panel.errors.add(:widgets, "#{message} at index #{@index}")
  end
end
