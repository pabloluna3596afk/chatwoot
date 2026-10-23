require 'digest'

class AutomationRules::ContactUpdatedService
  DEDUPE_TTL = 10.minutes.to_i
  DAILY_LIMIT = 200
  DAILY_TTL = 2.days.to_i

  def initialize(rule, contact, changed_attributes)
    @rule = rule
    @contact = contact
    @account = contact.account
    @changes = relevant_changes(changed_attributes)
  end

  def perform
    return if @changes.empty?

    conversation = target_conversation
    unless conversation
      Rails.logger.info("[ContactUpdated] no open/pending conversation rule=#{@rule.id} contact=#{@contact.id}")
      return
    end
    return unless AutomationRules::ConditionsFilterService.new(@rule, conversation, changed_attributes: filter_changes).perform
    return unless ::Redis::Alfred.set(dedupe_key, '1', nx: true, ex: DEDUPE_TTL)
    return unless reserve_daily_execution

    AutomationRules::ActionService.new(@rule, @account, conversation).perform
  end

  private

  def relevant_changes(changed_attributes)
    changes = changed_attributes.with_indifferent_access.slice(*@rule.conditions_attributes, 'custom_attributes', 'additional_attributes')
    return changes unless changes.key?('additional_attributes')

    before, after = changes['additional_attributes'].map { |value| (value || {}).slice(*@rule.conditions_attributes) }
    if before == after
      changes.delete('additional_attributes')
    else
      changes['additional_attributes'] = [before, after]
    end
    changes
  end

  def target_conversation
    conversations = @account.conversations.where(contact_id: @contact.id, status: %i[open pending])
    @rule.conditions.each do |condition|
      next unless condition['attribute_key'] == 'inbox_id' && condition['filter_operator'] == 'equal_to'

      conversations = conversations.where(inbox_id: condition['values'])
    end
    conversations.order(created_at: :desc, id: :desc).first
  end

  # previous_changes stores JSON attributes as whole hashes; the evaluator needs each changed key's pair.
  def filter_changes
    changes = @changes.dup
    %w[custom_attributes additional_attributes].each do |attribute|
      next unless @changes.key?(attribute)

      before, after = @changes[attribute].map { |value| value || {} }
      (before.keys | after.keys).each do |key|
        changes[key] = [before[key], after[key]] unless before[key] == after[key]
      end
    end
    changes
  end

  def dedupe_key
    digest = Digest::SHA256.hexdigest(canonical_changes(@changes).to_json)
    "automation:contact_updated:#{@rule.id}:#{@contact.id}:#{digest}"
  end

  def canonical_changes(value)
    case value
    when Hash then value.sort.to_h.transform_values { |item| canonical_changes(item) }
    when Array then value.map { |item| canonical_changes(item) }
    else value
    end
  end

  # This counts executions (including non-send actions), independently of the configurable proactive send cap.
  def reserve_daily_execution
    key = "automation:contact_updated:daily:#{@account.id}:#{Time.zone.today}"
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, DAILY_TTL) if count == 1
    return true if count <= DAILY_LIMIT

    Rails.logger.info("[ContactUpdated] daily limit reached account=#{@account.id} rule=#{@rule.id}")
    false
  end
end
