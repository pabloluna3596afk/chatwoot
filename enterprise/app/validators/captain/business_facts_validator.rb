class Captain::BusinessFactsValidator < ActiveModel::Validator
  FIELDS = %w[hours address payment_methods delivery booking].freeze
  MAX_LENGTH = 300

  def validate(record)
    facts = record.config['business_facts']
    return if facts.nil?

    unless facts.is_a?(Hash) && (facts.keys - FIELDS).empty? &&
           facts.values.all? { |value| value.is_a?(String) && value.length <= MAX_LENGTH }
      record.errors.add(:config, 'business_facts must contain only known fields with text up to 300 characters')
    end
  end
end
