require 'fileutils'

class Captain::Eval::Report
  TOKEN_COLUMNS = %i[input_tokens cached_input_tokens output_tokens reasoning_tokens].freeze

  def initialize(results:, account:, started_at:, settings: {}, directory: Rails.root.join('tmp/captain_eval'))
    @results = results
    @account = account
    @started_at = started_at
    @finished_at = Time.current
    @settings = settings
    @directory = directory
  end

  def write
    FileUtils.mkdir_p(@directory)
    path = File.join(@directory, "report-#{@started_at.strftime('%Y%m%d-%H%M')}")
    data = to_h
    File.write("#{path}.json", JSON.pretty_generate(data))
    File.write("#{path}.md", markdown(data))
    { markdown: "#{path}.md", json: "#{path}.json", totals: data[:totals] }
  end

  def to_h
    { started_at: @started_at.iso8601, finished_at: @finished_at.iso8601, account_id: @account.id, settings: @settings,
      totals: summary(@results), by_vertical: grouped_summary(:vertical), by_type: grouped_summary(:type),
      usage: usage, cases: @results }
  end

  private

  def summary(results)
    passed = results.count { |result| result[:passed] }
    { total: results.size, passed: passed, failed: results.size - passed,
      pass_percent: results.empty? ? 0 : (100.0 * passed / results.size).round(2) }
  end

  def grouped_summary(key)
    @results.group_by { |result| result.fetch(key) }.transform_values { |results| summary(results) }
  end

  def usage
    events = AiUsageEvent.where(account_id: @account.id, created_at: @started_at..@finished_at).to_a
    missing = events.reject { |event| priced?(event) }.map(&:model).uniq
    { cost_usd: events.sum(&:cost_usd).to_s, unpriced_models: missing, event_count: events.size,
      pricing: missing.empty? ? 'configurada' : 'tarifa no configurada',
      tokens: TOKEN_COLUMNS.index_with { |column| events.sum { |event| event.public_send(column) } } }
  end

  def priced?(event)
    price = AiModelPrice.current_for(event.model, at: event.created_at)
    price && [price.input_per_million, price.cached_input_per_million, price.output_per_million].any?(&:positive?)
  end

  def markdown(data)
    lines = report_header(data)
    %i[by_vertical by_type].each do |key|
      lines.push('', "## #{key}", '', '| Grupo | Aprobados | Porcentaje |', '| --- | --- | --- |')
      data[key].each { |group, totals| lines << "| #{group} | #{totals[:passed]}/#{totals[:total]} | #{totals[:pass_percent]} % |" }
    end
    lines.push('', '## Casos', '', '| Caso | Resultado | Comprobación fallida | Respuesta completa |', '| --- | --- | --- | --- |')
    lines.concat(case_rows)
    "#{lines.join("\n")}\n"
  end

  def report_header(data)
    ['# Evaluación Captain', '', "Inicio: #{data[:started_at]}", "Configuración: #{@settings.to_json}", '',
     "Aprobados: #{data[:totals][:passed]}/#{data[:totals][:total]} (#{data[:totals][:pass_percent]} %)", '',
     "Costo registrado (USD): #{data[:usage][:cost_usd]}; #{data[:usage][:pricing]}",
     "Modelos sin tarifa: #{data[:usage][:unpriced_models].join(', ')}", "Tokens: #{data[:usage][:tokens].to_json}"]
  end

  def case_rows
    lines = []
    @results.each do |result|
      result[:attempts].each_with_index do |attempt, index|
        failures = Array(attempt[:checks]).reject { |check| check[:passed] }.pluck(:reason)
        failures << attempt[:error] if attempt[:error]
        cells = ["#{result[:id]} (#{index + 1})", attempt[:passed] ? 'PASS' : 'FAIL', failures.join('; '), attempt[:response]]
        lines << "| #{cells.map { |cell| ERB::Util.html_escape(cell.to_s).gsub('|', '&#124;').gsub(/\r?\n/, '<br>') }.join(' | ')} |"
      end
    end
    lines
  end
end
