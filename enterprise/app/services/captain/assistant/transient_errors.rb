# Provider failures worth one more try a few seconds later: timeouts, rate limits and server errors.
module Captain::Assistant::TransientErrors
  CLASS_NAMES = %w[
    RubyLLM::RateLimitError RubyLLM::ServerError RubyLLM::ServiceUnavailableError RubyLLM::OverloadedError
    Faraday::TimeoutError Faraday::ConnectionFailed Faraday::ServerError Faraday::TooManyRequestsError
    Net::ReadTimeout Net::OpenTimeout Timeout::Error Errno::ECONNRESET Errno::ETIMEDOUT
  ].freeze
  SIDE_EFFECTS = Concurrent::Map.new

  def self.match?(error)
    seen = []
    while error && seen.exclude?(error)
      return true if classes.any? { |klass| error.is_a?(klass) }

      seen << error
      error = error.cause
    end
    false
  end

  def self.classes
    @classes ||= CLASS_NAMES.filter_map(&:safe_constantize)
  end

  # A tool that changes something already ran in this attempt: never run the turn again.
  def self.side_effect_ran?(conversation_id)
    SIDE_EFFECTS[conversation_id] == true if conversation_id
  end

  def self.mark_side_effect!(conversation_id)
    SIDE_EFFECTS[conversation_id] = true if conversation_id
  end

  def self.reset!(conversation_id)
    SIDE_EFFECTS.delete(conversation_id) if conversation_id
  end

  def self.retryable?(error, conversation_id)
    conversation_id.present? && match?(error) && !side_effect_ran?(conversation_id)
  end
end
