class Captain::InboxAudienceValidator < ActiveModel::Validator
  MODES = %w[inherit everyone custom].freeze
  LIST_KEYS = %w[phones channel_ids emails].freeze
  RULE_KEYS = (LIST_KEYS + %w[tree contact_scope]).freeze
  CONTACT_SCOPES = %w[all new returning].freeze
  MAX_ENTRIES = 1000
  MAX_ENTRY_LENGTH = 120

  def validate(record)
    record.errors.add(:audience_mode, 'is invalid') unless MODES.include?(record.audience_mode)
    return if valid_rules?(record.audience_rules, record.captain_assistant.account)

    record.errors.add(:audience_rules, 'must contain only valid audience rules')
  end

  private

  def valid_rules?(rules, account)
    return false unless rules.is_a?(Hash) && (rules.keys - RULE_KEYS).empty?
    return false unless valid_scope_and_lists?(rules)
    return true unless rules.key?('tree')

    Captain::AudienceValidator.new.valid_tree?(rules['tree'], account) && known_tree_keys?(rules['tree'])
  end

  def valid_scope_and_lists?(rules)
    return false if rules.key?('contact_scope') && CONTACT_SCOPES.exclude?(rules['contact_scope'])

    rules.slice(*LIST_KEYS).values.all? { |rule| valid_list?(rule) }
  end

  def valid_list?(rule)
    return false unless rule.is_a?(Hash) && rule.keys.sort == %w[list mode]
    return false unless %w[allow deny].include?(rule['mode'])

    valid_entries?(rule['list'])
  end

  def valid_entries?(entries)
    entries.is_a?(Array) && entries.size <= MAX_ENTRIES &&
      entries.all? { |entry| entry.is_a?(String) && entry.present? && entry.length <= MAX_ENTRY_LENGTH }
  end

  def known_tree_keys?(node)
    if node.key?('conditions')
      (node.keys - %w[operator conditions]).empty? && node['conditions'].all? { |child| known_tree_keys?(child) }
    else
      (node.keys - %w[attribute_key filter_operator values]).empty? && valid_tree_values?(node)
    end
  end

  def valid_tree_values?(node)
    return true unless node.key?('values')

    node['values'].is_a?(Array) && node['values'].none? { |value| value.is_a?(Hash) || value.is_a?(Array) }
  end
end
