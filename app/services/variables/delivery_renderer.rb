class Variables::DeliveryRenderer
  class Error < StandardError
    attr_reader :status, :path

    def initialize(status:, path:)
      @status = status
      @path = path
      super("#{path}: #{status}")
    end
  end

  def initialize(drops:)
    @resolver = Variables::Resolver.new(drops: drops)
  end

  def render(value, path: 'content', protect_code: false)
    case value
    when Hash
      value.to_h { |key, item| [key, render(item, path: "#{path}.#{key}", protect_code: protect_code)] }
    when Array
      value.each_with_index.map { |item, index| render(item, path: "#{path}[#{index}]", protect_code: protect_code) }
    when String
      render_text(value, path, protect_code)
    else
      value
    end
  end

  private

  def render_text(value, path, protect_code)
    return value if value.empty?

    result = @resolver.preview(value, protect_code: protect_code, diagnose_outputs: true)
    raise Error.new(status: result[:status], path: path) unless result[:status] == 'value'

    result[:value]
  end
end
