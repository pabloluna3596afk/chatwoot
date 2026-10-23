class Conversations::SnoozeParameters
  UNIT_DURATIONS = { 'minutes' => 1.minute, 'hours' => 1.hour, 'days' => 1.day }.freeze
  MAX_DURATION = 365.days

  def initialize(params)
    @params = params
    data = params.is_a?(Array) ? params.first : params
    @data = data.with_indifferent_access if data.is_a?(Hash)
  end

  def parameterless?
    @params.nil? || @params == []
  end

  def error
    return if parameterless?
    return 'snooze_conversation requires duration and unit.' unless @data
    return 'snooze_conversation duration must be a positive integer.' unless @data[:duration].is_a?(Integer) && @data[:duration].positive?
    return 'snooze_conversation unit must be minutes, hours or days.' unless UNIT_DURATIONS.key?(@data[:unit])
    return if duration <= MAX_DURATION

    'snooze_conversation duration must not exceed 365 days.'
  end

  def duration
    @data[:duration] * UNIT_DURATIONS.fetch(@data[:unit])
  end
end
