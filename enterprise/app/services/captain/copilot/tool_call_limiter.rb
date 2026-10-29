class Captain::Copilot::ToolCallLimiter
  MAX_CALLS_PER_TURN = 20

  def initialize
    @calls = 0
    @mutex = Mutex.new
    @turn_id = SecureRandom.hex(12)
  end

  attr_reader :turn_id

  def consume!
    @mutex.synchronize do
      @calls += 1
      raise ArgumentError, "Copilot allows at most #{MAX_CALLS_PER_TURN} tool calls per turn" if @calls > MAX_CALLS_PER_TURN

      @calls
    end
  end
end
