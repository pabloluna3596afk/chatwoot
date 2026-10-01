class Captain::FollowupValidator < ActiveModel::Validator
  Settings = Captain::FollowupSettings

  def validate(record)
    validate_paid_templates(record)

    raw = record.config['followup']
    return if raw.nil?
    return record.errors.add(:config, 'followup must be an object') unless raw.is_a?(Hash)

    settings = Settings.new(raw)
    validate_numbers(record, settings)
    validate_template(record, settings)
  end

  private

  def validate_paid_templates(record)
    value = record.config['allow_paid_templates']
    return if value.nil? || [true, false].include?(value)

    record.errors.add(:config, 'allow_paid_templates must be true or false')
  end

  def validate_numbers(record, settings)
    {
      inactivity_after_minutes: Settings::INACTIVITY_AFTER_RANGE,
      max_nudges: Settings::MAX_NUDGES_RANGE,
      close_after_minutes: Settings::CLOSE_AFTER_RANGE
    }.each do |key, range|
      value = settings.public_send(key)
      next if value.is_a?(Integer) && range.cover?(value)

      record.errors.add(:config, "followup #{key} must be between #{range.min} and #{range.max}")
    end
  end

  def validate_template(record, settings)
    template = settings.reengagement_template
    return if template.nil?
    return if template.is_a?(Hash) && template['name'].present? && template['language'].present?

    record.errors.add(:config, 'followup reengagement_template must have a name and a language')
  end
end
