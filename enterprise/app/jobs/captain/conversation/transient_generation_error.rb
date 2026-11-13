class Captain::Conversation::TransientGenerationError < StandardError
  attr_reader :reason

  def initialize(reason)
    @reason = reason
    super("Transient Captain generation failure: #{reason}")
  end
end
