require 'yaml'

class Captain::Eval::Suite
  DIRECTORY = File.expand_path('cases', __dir__).freeze
  TEXT_FIELDS = %w[question answer].freeze
  CASE_FIELDS = %w[id title].freeze
  class InvalidSuite < StandardError; end

  attr_reader :verticals

  def initialize(names: nil, directory: DIRECTORY)
    files = Dir[File.join(directory, '*.yml')]
    selected = names ? names.split(',') : files.map { |file| File.basename(file, '.yml') }
    raise InvalidSuite, 'CASES debe seleccionar al menos una vertical' if selected.empty?

    @verticals = selected.map do |name|
      file = files.find { |candidate| File.basename(candidate, '.yml') == name }
      raise InvalidSuite, "Vertical desconocida: #{name}" unless file

      load_file(file)
    end
  end

  private

  def load_file(file)
    data = YAML.safe_load_file(file)
    validate!(data.is_a?(Hash), file, 'documento')
    validate!(data['vertical'].is_a?(String) && data['vertical'].present?, file, 'vertical')
    validate_assistant(data['assistant'], file)
    validate_knowledge(data['knowledge'], file)
    validate_cases(data['cases'], file)
    data
  rescue Psych::Exception => e
    raise InvalidSuite, "#{file}: #{e.message}"
  end

  def validate_assistant(assistant, file)
    validate!(assistant.is_a?(Hash), file, 'assistant')
    %w[name description].each { |key| validate!(assistant[key].is_a?(String) && assistant[key].present?, file, "assistant.#{key}") }
    %w[guidelines guardrails].each { |key| validate!(strings?(assistant[key]), file, "assistant.#{key}") }
  end

  def validate_knowledge(knowledge, file)
    validate!(knowledge.is_a?(Array) && knowledge.present?, file, 'knowledge')
    knowledge.each do |pair|
      valid = pair.is_a?(Hash) && TEXT_FIELDS.all? { |key| pair[key].is_a?(String) && pair[key].present? }
      validate!(valid, file, 'knowledge.question/answer')
    end
  end

  def validate_cases(cases, file)
    validate!(cases.is_a?(Array) && cases.present?, file, 'cases')
    cases.each { |item| validate_case(item, file) }
    validate!(cases.pluck('id').uniq.size == cases.size, file, 'ids únicos')
  end

  def validate_case(item, file)
    validate!(item.is_a?(Hash), file, 'case')
    CASE_FIELDS.each { |key| validate!(item[key].is_a?(String) && item[key].present?, file, "case.#{key}") }
    validate!(strings?(item['turns']) && item['turns'].present?, file, "#{item['id']}.turns")
    validate!(item['expect'].is_a?(Hash), file, "#{item['id']}.expect")
    item['expect'].each { |key, value| validate_check(key, value, file) }
  end

  def validate_check(key, value, file) # rubocop:disable Metrics/CyclomaticComplexity
    valid = case key
            when 'includes_any', 'includes_all', 'excludes' then strings?(value) && value.present?
            when 'max_chars' then value.is_a?(Integer) && value.positive?
            when 'tool_called', 'tool_not_called' then value.is_a?(String) && value.present?
            when 'handoff' then [true, false].include?(value)
            when 'language' then %w[es en].include?(value)
            else false
            end
    validate!(valid, file, "comprobación #{key}")
  end

  def strings?(value)
    value.is_a?(Array) && value.all? { |item| item.is_a?(String) && item.present? }
  end

  def validate!(condition, file, field)
    raise InvalidSuite, "#{file}: campo inválido o ausente: #{field}" unless condition
  end
end
