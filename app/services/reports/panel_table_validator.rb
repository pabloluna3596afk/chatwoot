class Reports::PanelTableValidator
  COLUMNS = {
    'conversations' => %w[id contact_name status priority labels inbox assignee created_at last_activity_at],
    'contacts' => %w[id name phone_number email document_number labels conversations_count assignee inbox created_at last_activity_at]
  }.freeze

  def initialize(panel, widget, index)
    @panel = panel
    @widget = widget
    @index = index
    @kind = widget[:table_kind]
  end

  def validate
    error('invalid table kind') unless SavedReportPanel::TABLE_KINDS.include?(@kind)
    if @kind == 'pivot'
      Reports::PanelPivotValidator.new(@panel, @widget, @index).validate
    else
      error('pivot requires a pivot table') if @widget.key?(:pivot)
      validate_columns
    end
    validate_aggregations
  end

  private

  def validate_columns
    columns = @widget[:columns]
    return if columns.nil?
    return error('invalid columns') unless columns.is_a?(Array) && columns.all?(String)

    allowed = COLUMNS.fetch(@kind, [])
    invalid = columns.reject { |key| allowed.include?(key) || custom_column?(key) }
    error("invalid columns: #{invalid.join(', ')}") if invalid.any?
  end

  def custom_column?(key)
    key.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)
  end

  def validate_aggregations
    aggregations = @widget[:column_aggregations]
    return if aggregations.nil?
    return error('invalid column_aggregations') unless aggregations.is_a?(Hash)

    columns = @widget[:columns].is_a?(Array) ? @widget[:columns] : []
    aggregations.each do |key, op|
      error("column_aggregations key not in columns: #{key}") unless columns.include?(key)
      error("invalid column aggregation '#{op}'") unless SavedReportPanel::COLUMN_AGGREGATION_OPS.include?(op)
    end
  end

  def error(message)
    @panel.errors.add(:widgets, "#{message} at index #{@index}")
  end
end
