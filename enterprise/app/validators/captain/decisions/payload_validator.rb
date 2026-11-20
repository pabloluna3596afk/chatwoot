# Version 1 stores references and bounded structured facts, never transcripts or tool arguments.
class Captain::Decisions::PayloadValidator < ActiveModel::Validator
  ID_LISTS = %w[document_ids cited_document_ids faq_ids used_faq_ids].freeze
  MESSAGE_IDS = %w[last_customer_message_id evaluated_through_message_id].freeze
  FLAGS = %w[complete customer_confirmed expects_customer_reply probable_complete].freeze
  ENUMS = {
    'action' => %w[reply resolve handoff],
    'cancellation_cause' => %w[new_incoming human_reply conversation_changed turn_changed],
    'error' => %w[evaluation_failed evaluation_interrupted],
    'reason_category' => %w[customer_request missing_knowledge unsupported_request policy_restriction tool_failure pending_clarification unknown]
  }.freeze
  SETTINGS = %w[inactivity_threshold_minutes completion_grace_minutes].freeze

  def validate(record)
    validate_evidence(record)
    validate_source_references(record)
    validate_settings(record)
    validate_technical(record)
    objects = [record.evidence, record.settings_snapshot, record.technical_details]
    return unless objects.all?(Hash)

    # PostgreSQL jsonb text includes spaces after separators. Include container whitespace to keep this precheck conservative.
    bytes = objects.sum { |value| JSON.generate(value, space: ' ', object_nl: ' ', array_nl: ' ').bytesize }
    record.errors.add(:base, 'decision payload exceeds 8 KiB') if bytes > Captain::Decision::PAYLOAD_LIMIT
  end

  private

  def validate_evidence(record)
    validate_object(record, :evidence, ID_LISTS + MESSAGE_IDS + FLAGS + ENUMS.keys + %w[tools team_id assignee_id]) do |key, value|
      evidence_value_valid?(key, value)
    end
    return unless record.evidence.is_a?(Hash)

    ids = record.evidence.slice(*MESSAGE_IDS).values
    return if ids.empty? || record.conversation&.messages&.where(id: ids)&.count == ids.uniq.size

    record.errors.add(:evidence, 'message references must belong to this conversation')
  end

  def evidence_value_valid?(key, value)
    return id_list?(value) if ID_LISTS.include?(key)
    return positive_id?(value) if MESSAGE_IDS.include?(key) || %w[team_id assignee_id].include?(key)
    return [true, false].include?(value) if FLAGS.include?(key)
    return tool_list?(value) if key == 'tools'

    ENUMS.fetch(key).include?(value)
  end

  def id_list?(value)
    value.is_a?(Array) && value.size <= 100 && value.all? { |id| positive_id?(id) }
  end

  def tool_list?(value)
    value.is_a?(Array) && value.size <= 50 && value.all? { |name| name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]{0,79}\z/) }
  end

  def validate_source_references(record)
    return unless record.evidence.is_a?(Hash)

    { 'document_ids' => Captain::Document, 'cited_document_ids' => Captain::Document,
      'faq_ids' => Captain::AssistantResponse, 'used_faq_ids' => Captain::AssistantResponse }.each do |key, klass|
      ids = record.evidence[key]
      next unless ids.is_a?(Array) && ids.all? { |id| positive_id?(id) }
      next if klass.where(account_id: record.account_id, assistant_id: record.assistant_id, id: ids).count == ids.uniq.size

      record.errors.add(:evidence, 'sources must belong to the decision assistant and account')
    end
    validate_routing_references(record)
  end

  def validate_routing_references(record)
    { 'team_id' => Team, 'assignee_id' => User }.each do |key, klass|
      id = record.evidence[key]
      next unless positive_id?(id)

      scope = klass == User ? record.account.users : klass.where(account_id: record.account_id)
      record.errors.add(:evidence, 'routing must belong to the decision account') unless scope.exists?(id: id)
    end
  end

  def validate_settings(record)
    validate_object(record, :settings_snapshot, SETTINGS) { |_key, value| value.is_a?(Integer) && value.positive? }
  end

  def validate_technical(record)
    validate_object(record, :technical_details, %w[model credits_consumed cost]) do |key, value|
      key == 'model' ? value.is_a?(String) && value.length.between?(1, 120) : value.is_a?(Numeric) && value.finite? && value >= 0
    end
  end

  def validate_object(record, attribute, keys, &)
    value = record.public_send(attribute)
    valid = value.is_a?(Hash) && (value.keys - keys).empty? && value.all?(&)
    record.errors.add(attribute, 'does not match the version 1 schema') unless valid
  end

  def positive_id?(value)
    value.is_a?(Integer) && value.positive?
  end
end
