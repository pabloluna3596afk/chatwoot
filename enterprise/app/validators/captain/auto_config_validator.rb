class Captain::AutoConfigValidator
  MAX_RESOURCES = Captain::MessagingValidator::MAX_RESOURCES
  MAX_PURPOSE_LENGTH = Captain::MessagingValidator::MAX_PURPOSE_LENGTH

  def initialize(record)
    @record = record
  end

  def validate(entry)
    validate_scoped_keys(entry['excluded'], %w[templates flows], 'excluded') if entry.key?('excluded')
    validate_scoped_keys(entry['included_marketing'], nil, 'included_marketing') if entry.key?('included_marketing')
    validate_notes(entry['notes']) if entry.key?('notes')
    validate_params(entry['params']) if entry.key?('params')
    validate_reviewed(entry['reviewed']) if entry.key?('reviewed')
  end

  private

  def error(message)
    @record.errors.add(:config, "messaging #{message}")
  end

  def unknown_keys(where, hash, allowed)
    extra = hash.keys.map(&:to_s) - allowed
    error("#{where} has unknown keys: #{extra.join(', ')}") if extra.any?
  end

  def validate_scoped_keys(value, kinds, label)
    lists = scoped_lists(value, kinds, label)
    lists&.each { |kind, list| validate_scoped_list(kind, list, label) }
  end

  def scoped_lists(value, kinds, label)
    return { label => value } unless kinds

    unless value.is_a?(Hash)
      error("#{label} must be an object")
      return
    end

    unknown_keys(label, value, kinds)
    kinds.index_with { |kind| value.fetch(kind, []) }
  end

  def validate_scoped_list(kind, list, label)
    return error("#{label} #{kind} must be a list") unless list.is_a?(Array)
    return error("#{label} #{kind} cannot have more than #{MAX_RESOURCES} entries") if list.size > MAX_RESOURCES

    error("#{label} #{kind} cannot repeat entries") unless list.uniq.size == list.size
    list.each { |item| validate_scoped_item(kind, item, label) }
  end

  def validate_scoped_item(kind, item, label)
    pattern = kind == 'flows' ? /\A\d+:\d+\z/ : /\A\d+:[^|]+\|[^|]+\z/
    return if item.is_a?(String) && item.match?(pattern)

    error("#{label} #{kind} entries must include a WABA-scoped resource identity")
  end

  def validate_notes(notes)
    return error('notes must be an object') unless notes.is_a?(Hash)

    notes.each do |key, value|
      valid_key = key.to_s.match?(/\A(?:template:\d+:[^|]+\|[^|]+|flow:\d+:\d+)\z/)
      error("note key #{key.inspect} is invalid") unless valid_key
      error("note #{key.inspect} must be a text up to #{MAX_PURPOSE_LENGTH} characters") unless valid_note?(value)
    end
  end

  def valid_note?(value)
    value.is_a?(String) && value.length <= MAX_PURPOSE_LENGTH
  end

  def validate_params(params)
    return error('params must be an object') unless params.is_a?(Hash)

    params.each { |key, values| validate_params_entry(key, values) }
  end

  def validate_params_entry(key, values)
    match = /\A\d+:([^|]+)\|([^|]+)\z/.match(key.to_s)
    unless match && values.is_a?(Hash)
      error("params key #{key.inspect} must include a WABA-scoped template identity")
      return
    end
    reference = { 'name' => match[1], 'language' => match[2], 'processed_params' => values }
    Captain::TemplateReference.errors(reference, @record.account).each { |message| error("params #{key} #{message}") }
  end

  def validate_reviewed(reviewed)
    return error('reviewed must be an object') unless reviewed.is_a?(Hash)

    unknown_keys('reviewed', reviewed, %w[templates flows])
    %w[templates flows].each { |kind| validate_reviewed_resources(kind, reviewed.fetch(kind, {})) }
  end

  def validate_reviewed_resources(kind, resources)
    return error("reviewed #{kind} must be an object") unless resources.is_a?(Hash)

    resources.each { |key, value| validate_reviewed_entry(kind, key, value) }
  end

  def validate_reviewed_entry(kind, key, value)
    valid_key = kind == 'templates' ? key.to_s.match?(/\A\d+:[^|]+\|[^|]+\z/) : key.to_s.match?(/\A\d+:\d+\z/)
    valid_value = kind == 'templates' ? value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) : value.is_a?(Integer) && value.positive?
    error("reviewed #{kind} entry #{key.inspect} is invalid") unless valid_key && valid_value
  end
end
