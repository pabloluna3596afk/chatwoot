class Reports::PanelPivotPercentages
  def initialize(displays:, measures:, values:)
    @displays = displays
    @measures = measures
    @values = values
  end

  def apply(population, selected, totals)
    @measures.each do |measure|
      mode = @displays.fetch(measure.key, 'value')
      next if mode == 'value'

      columns = [measure.key] + @values.map { |value| measure.column_key(value) }
      denominators = columns.index_with { |column| population.sum { |row| row[column].to_f } }
      selected.each { |row| convert_row(row, measure.key, mode, denominators) }
      convert_totals(totals, measure.key, mode, denominators)
    end
  end

  private

  def convert_row(row, measure, mode, denominators)
    row_total = row.fetch(measure).to_f
    denominators.each do |column, total|
      row[column] = percentage(row[column], mode == 'row_percent' ? row_total : total)
    end
  end

  def convert_totals(totals, measure, mode, denominators)
    denominators.each do |column, total|
      next unless totals[:columns].key?(column)

      denominator = mode == 'row_percent' ? denominators.fetch(measure) : total
      totals[:columns][column] = percentage(total, denominator)
    end
  end

  def percentage(value, denominator)
    denominator.zero? ? nil : (value.to_f / denominator * 100).round(2)
  end
end
