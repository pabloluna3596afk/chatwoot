class Captain::Audience::Evaluator
  def initialize(assistant, inbox)
    @assistant = assistant
    @connection = assistant.captain_inboxes.find_by(inbox_id: inbox.id)
  end

  def result(contact, conversation)
    @contact = contact
    @conversation = conversation
    failure = audience_failure
    return failure if failure
    return rejected('out_of_hours') unless @assistant.available_now?(conversation)

    { engages: true, reason: nil, condition: nil }
  end

  private

  def audience_failure
    case @connection&.audience_mode || 'inherit'
    when 'everyone' then nil
    when 'inherit' then tree_failure(@assistant.config['audience'])
    when 'custom' then custom_failure
    end
  end

  def custom_failure
    @rules = @connection.audience_rules
    @lists = Captain::Audience::ListMatcher.new(@contact, @conversation)
    list_failure('deny') || list_failure('allow') || tree_failure(@rules['tree']) || scope_failure
  end

  def list_failure(mode)
    @rules.slice(*Captain::InboxAudienceValidator::LIST_KEYS).each do |type, rule|
      next unless rule['mode'] == mode

      failure = list_rejection(type, mode, rule['list'])
      return failure if failure
    end
    nil
  end

  def list_rejection(type, mode, entries)
    matches = @lists.matches?(type, entries)
    return matches ? rejected('audience_denied', list_condition(type)) : nil if mode == 'deny'
    return if matches

    reason = @lists.missing?(type) ? 'audience_missing_data' : 'audience_not_allowed'
    rejected(reason, list_condition(type))
  end

  def list_condition(type)
    { attribute_key: { 'phones' => 'phone_number', 'emails' => 'email', 'channel_ids' => 'channel_ids' }.fetch(type) }
  end

  def tree_failure(tree)
    failure = Captain::AudienceMatcher.new(tree).first_failure(@contact, @conversation)
    return unless failure

    reason = failure[:missing_data] ? 'audience_missing_data' : 'audience_no_match'
    rejected(reason, failure[:condition])
  end

  def scope_failure
    scope = @rules.fetch('contact_scope', 'all')
    return if scope == 'all'

    previous = @contact.conversations.where(account_id: @conversation.account_id).where.not(id: @conversation.id)
    previous = previous.where(created_at: ..@conversation.created_at) if @conversation.persisted?
    returning = previous.exists?
    return if scope == 'returning' ? returning : !returning

    rejected('audience_scope', { contact_scope: scope })
  end

  def rejected(reason, condition = nil)
    { engages: false, reason: reason, condition: condition }
  end
end
