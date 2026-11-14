class Captain::Eval::Checks
  WORDS = {
    'es' => %w[el la los las un una de del en con por para que es son esta estamos nuestro nuestra tu su te le y o si no como puedo gracias],
    'en' => %w[the a an of in on with for to is are we our your you can will do have this that and or if not how help please thank thanks]
  }.freeze

  def self.normalize(text)
    I18n.transliterate(text.to_s).downcase
  end

  def initialize(response:, tools:, handoff:)
    @response = response
    @text = self.class.normalize(response)
    @tools = tools
    @handoff = handoff
  end

  def perform(expectations)
    expectations.map do |name, expected|
      passed = public_send(name, expected)
      { check: name, passed: passed, reason: passed ? nil : "#{name}: esperado #{expected.inspect}" }
    end
  end

  def includes_any(values) = values.any? { |value| @text.include?(self.class.normalize(value)) }
  def includes_all(values) = values.all? { |value| @text.include?(self.class.normalize(value)) }
  def excludes(values) = values.none? { |value| @text.include?(self.class.normalize(value)) }
  def max_chars(value) = @response.length <= value
  def tool_called(value) = @tools.include?(value)
  def tool_not_called(value) = !tool_called(value)
  def handoff(value) = @handoff == value

  def language(value)
    words = @text.scan(/[a-z]+/)
    scores = WORDS.transform_values { |vocabulary| words.count { |word| vocabulary.include?(word) } }
    scores.fetch(value).positive? && scores.fetch(value) > scores.fetch(value == 'es' ? 'en' : 'es')
  end
end
