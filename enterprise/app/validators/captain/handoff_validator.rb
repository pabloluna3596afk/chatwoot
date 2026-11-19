class Captain::HandoffValidator < ActiveModel::Validator
  MODES = %w[inbox last_agent team ai_team].freeze
  PRIORITIES = %w[off on_signal always].freeze
  KINDS = %w[new reopened].freeze

  def validate(record)
    error(record, 'handoff_priority') if record.config.key?('handoff_priority') && PRIORITIES.exclude?(record.config['handoff_priority'])
    return unless record.config.key?('handoff_routing')

    routing = record.config['handoff_routing']
    return error(record, 'handoff_routing') unless routing.is_a?(Hash) && (routing.keys - KINDS).empty?

    routing.each_value { |row| validate_row(record, row) }
  end

  private

  def validate_row(record, row)
    return error(record, 'handoff_routing') unless valid_row?(row)

    if row['mode'] == 'team'
      id = row['team_id']
      error(record, 'handoff_team') unless id.is_a?(Integer) && record.account.teams.exists?(id: id)
    elsif !row['team_id'].nil?
      error(record, 'handoff_team_unused')
    end
  end

  def valid_row?(row)
    row.is_a?(Hash) && (row.keys - %w[mode team_id]).empty? && MODES.include?(row['mode'])
  end

  def error(record, key)
    record.errors.add(:config, I18n.t("captain.assistant.errors.#{key}", locale: record.account.locale))
  end
end
