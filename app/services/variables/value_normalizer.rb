class Variables::ValueNormalizer
  def initialize(drops:)
    @drops = drops
  end

  def normalize(definition, raw_value)
    return Array.wrap(raw_value).map { |item| render_custom_attribute_template(item) } if definition.attribute_display_type == 'multi_list'

    rendered = render_custom_attribute_template(raw_value)

    normalize_scalar(definition.attribute_display_type, rendered)
  end

  private

  def normalize_scalar(type, rendered)
    case type
    when 'number', 'currency', 'percent'
      Float(rendered)
    when 'checkbox'
      ActiveModel::Type::Boolean.new.cast(rendered)
    when 'date'
      parse_custom_attribute_date(rendered)
    when 'datetime'
      parse_custom_attribute_datetime(rendered)
    else
      # text, link, list, and any other type
      rendered.to_s
    end
  end

  def render_custom_attribute_template(raw_value)
    text = raw_value.to_s
    return text unless text.include?('{{') || text.include?('{%')

    Variables::Resolver.new(drops: @drops).render(text)
  end

  def parse_custom_attribute_date(rendered)
    return rendered.iso8601 if rendered.is_a?(Date)
    return rendered.to_date.iso8601 if rendered.is_a?(Time) || rendered.is_a?(DateTime)

    text = rendered.to_s.strip
    # Native date inputs and Liquid relative dates resolve to ISO YYYY-MM-DD:
    # {{ date.today }}, {{ date.today | plus_days: N }}, {{ date.today | minus_days: N }}.
    return Date.iso8601(text).iso8601 if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    %w[%d/%m/%Y %m/%d/%Y %Y/%m/%d].each do |fmt|
      return Date.strptime(text, fmt).iso8601
    rescue ArgumentError
      next
    end

    raise ArgumentError, "invalid date: #{text}"
  end

  def parse_custom_attribute_datetime(rendered)
    return rendered.iso8601 if rendered.is_a?(Time) || rendered.is_a?(DateTime)
    return rendered.to_time.iso8601 if rendered.is_a?(Date)

    text = rendered.to_s.strip
    parsed = Time.zone.parse(text)
    raise ArgumentError, "invalid datetime: #{text}" if parsed.blank?

    parsed.iso8601
  end
end
