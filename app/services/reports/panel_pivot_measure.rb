class Reports::PanelPivotMeasure
  SYSTEM_KEYS = %w[conversations_count resolved_conversations_count].freeze
  CUSTOM_KEY = /\A(ca|contact_ca):([\p{L}\p{N}_.\-]+)__(count|sum|avg|min|max)\z/

  attr_reader :key, :op, :attribute_key

  def initialize(key)
    @key = key
    match = CUSTOM_KEY.match(key)
    @attribute_key = match && match[2]
    @contact = match && match[1] == 'contact_ca'
    @op = match ? match[3] : 'count'
  end

  def contact?
    @contact
  end

  def additive?
    %w[count sum].include?(op)
  end

  def empty
    return {} if key == 'resolved_conversations_count'

    { sum: 0.0, count: 0, min: nil, max: nil, contacts: {} }
  end

  def accumulate(accumulator, conversation)
    return if key == 'resolved_conversations_count'

    record = contact? ? conversation.contact : conversation
    return if seen_contact?(accumulator, record)

    value = measure_value(record)
    add_value(accumulator, value) unless value.nil?
  end

  def merge(accumulators)
    return accumulators.each_with_object({}) { |accumulator, total| total.merge!(accumulator) } if key == 'resolved_conversations_count'

    accumulators.each_with_object(empty) do |accumulator, total|
      next if accumulator.empty?

      total[:sum] += accumulator[:sum]
      total[:count] += accumulator[:count]
      total[:min] = [total[:min], accumulator[:min]].compact.min
      total[:max] = [total[:max], accumulator[:max]].compact.max
    end
  end

  def combine(accumulators)
    total = merge(accumulators)
    return total.size if key == 'resolved_conversations_count'
    return total[:count] if op == 'count'
    return total[:sum].round(2) if op == 'sum'
    return nil if total[:count].zero?

    value = op == 'avg' ? total[:sum] / total[:count] : total.fetch(op.to_sym)
    value.round(2)
  end

  def footer_op
    op == 'count' ? 'sum' : op
  end

  def column_key(value)
    # Same bytes as the editor's encodeURIComponent plus !'()*~ (see panelConstants#pivotColumnKey).
    encoded = CGI.escape(value).gsub('+', '%20').gsub('~', '%7E')
    "#{key}__pv__#{encoded}"
  end

  private

  def seen_contact?(accumulator, record)
    return false unless contact?
    return true if accumulator[:contacts].key?(record.id)

    accumulator[:contacts][record.id] = true
    false
  end

  def measure_value(record)
    value = attribute_key ? record.custom_attributes[attribute_key] : 1
    return nil if value.nil? || value == '' || value == []

    op == 'count' ? 1 : CustomAttributes::NumericParser.parse(value)
  end

  def add_value(accumulator, value)
    accumulator[:sum] += value
    accumulator[:count] += 1
    accumulator[:min] = [accumulator[:min], value].compact.min
    accumulator[:max] = [accumulator[:max], value].compact.max
  end
end
