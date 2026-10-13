class Reports::PanelWidgetValidator
  DYNAMIC_OPTIONS = %w[sort top_n column_formats measure_display].freeze

  def initialize(panel)
    @panel = panel
  end

  def validate
    widgets = @panel.widgets
    return error('must be an array') unless widgets.is_a?(Array)
    return error('must include at least one widget') if widgets.empty?
    return error("cannot exceed #{SavedReportPanel::MAX_WIDGETS}") if widgets.size > SavedReportPanel::MAX_WIDGETS

    widgets.each_with_index { |widget, index| validate_widget(widget, index) }
  end

  private

  def validate_widget(raw, index)
    return error("invalid widget at index #{index}") unless raw.is_a?(Hash)

    widget = raw.with_indifferent_access
    return error("invalid type at index #{index}") unless SavedReportPanel::WIDGET_TYPES.include?(widget[:type])

    validate_scope(widget, index)
    if widget[:type] == 'table'
      Reports::PanelTableValidator.new(@panel, widget, index).validate
    else
      validate_metric(widget, index)
    end
    validate_options(widget, index)
  end

  def validate_options(widget, index)
    error("pivot requires a table at index #{index}") if widget.key?(:pivot) && widget[:type] != 'table'
    return unless DYNAMIC_OPTIONS.any? { |key| widget.key?(key) } && !widget.key?(:pivot)

    error("dynamic options require a pivot table at index #{index}")
  end

  def validate_scope(widget, index)
    scope = widget[:scope_type].presence || 'account'
    error("invalid scope at index #{index}") unless SavedReportPanel::SCOPE_TYPES.include?(scope)
  end

  def validate_metric(widget, index)
    source = widget[:source].presence || 'preset'
    return error("invalid metric source at index #{index}") unless SavedReportPanel::METRIC_SOURCES.include?(source)
    return validate_aggregation(widget, index) if source == 'aggregation'
    return if SavedReportPanel::ALLOWED_METRICS.include?(widget[:metric])

    error("invalid metric at index #{index}")
  end

  def validate_aggregation(widget, index)
    validate_aggregation_options(widget, index)
    %w[aggregation_field aggregation_group_field].each do |key|
      field = widget[key]
      error("invalid #{key} at index #{index}") if field.present? && !field.match?(/\Aca:[\p{L}\p{N}_.\-]+\z/)
    end
  end

  def validate_aggregation_options(widget, index)
    op = widget[:aggregation_op].presence || 'count'
    entity = widget[:aggregation_entity].presence || 'conversations'
    error("invalid aggregation op at index #{index}") unless SavedReportPanel::AGGREGATION_OPS.include?(op)
    error("invalid aggregation entity at index #{index}") unless SavedReportPanel::AGGREGATION_ENTITIES.include?(entity)
    error("aggregation field required at index #{index}") if op != 'count' && widget[:aggregation_field].blank?
  end

  def error(message)
    @panel.errors.add(:widgets, message)
  end
end
