class Captain::Playground::Input
  MESSAGE_LIMIT = 500
  HISTORY_LIMIT = 10
  HISTORY_CHARACTER_LIMIT = 4000

  def initialize(message:, history:)
    @message = message
    @history = history.nil? ? [] : history
  end

  def messages
    validate_message!
    validate_history!
    trim_history(normalized_history)
  end

  private

  def validate_message!
    return if @message.is_a?(String) && @message.present? && @message.length <= MESSAGE_LIMIT

    raise Captain::Playground::Usage::LimitExceeded.new('playground_message_invalid', status: :unprocessable_entity)
  end

  def validate_history!
    return if @history.is_a?(Array) && @history.all? { |message| valid_history_message?(message) }

    raise Captain::Playground::Usage::LimitExceeded.new('playground_history_invalid', status: :unprocessable_entity)
  end

  def normalized_history
    history = @history.map do |message|
      { role: message[:role], content: message[:content], agent_name: message[:agent_name] }.compact
    end
    history.pop if history.last&.slice(:role, :content) == current_message
    (history + [current_message]).last(HISTORY_LIMIT)
  end

  def current_message
    { role: 'user', content: @message }
  end

  def trim_history(history)
    history.shift while history.sum { |message| message[:content].length } > HISTORY_CHARACTER_LIMIT
    history
  end

  def valid_history_message?(message)
    message.respond_to?(:keys) && %w[user assistant].include?(message[:role]) && message[:content].is_a?(String) &&
      (!message.key?(:agent_name) || message[:agent_name].is_a?(String))
  end
end
