class ActionService
  include EmailHelper
  include FileTypeHelper

  def initialize(conversation)
    @conversation = conversation.reload
    @account = @conversation.account
  end

  def mute_conversation(_params)
    @conversation.mute!
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def create_internal_task(params)
    InternalTasks::AutomatedCreateService.new(conversation: @conversation, source: @rule || @macro, params: params).perform
  end

  def snooze_conversation(params)
    snooze = Conversations::SnoozeParameters.new(params)
    return @conversation.snoozed! if snooze.parameterless?

    error = snooze.error
    Rails.logger.error("[ActionService] rule_id=#{@rule&.id} conversation_id=#{@conversation.id}: #{error}") if error
    @conversation.update!(status: :snoozed, snoozed_until: error ? nil : Time.current + snooze.duration)
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def resolve_conversation(_params)
    @conversation.resolved!
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def open_conversation(_params)
    @conversation.open!
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def pending_conversation(_params)
    @conversation.pending!
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def change_status(status)
    @conversation.update!(status: status[0])
  rescue ActiveRecord::RecordInvalid => e
    record_business_rule_block!(e)
  end

  def change_priority(priority)
    @conversation.update!(priority: (priority[0] == 'nil' ? nil : priority[0]))
  end

  def add_label(labels)
    return if labels.empty?

    @conversation.reload.add_labels(labels)
  end

  def assign_agent(agent_ids = [])
    return assign_captain(agent_ids.first) if agent_ids.first.to_s.match?(/\Acaptain(?::[1-9]\d*)?\z/) && respond_to?(:assign_captain, true)

    if agent_ids[0] == 'nil'
      return Conversations::AssignmentService.new(conversation: @conversation, assignee_id: nil).perform
    end

    agent_ids = [last_responding_agent_id] if agent_ids[0] == 'last_responding_agent'
    return unless agent_belongs_to_inbox?(agent_ids)

    @agent = @account.users.find_by(id: agent_ids)
    return unless @agent.present? && @agent.confirmed?

    Conversations::AssignmentService.new(conversation: @conversation, assignee_id: @agent.id).perform
  end

  def remove_label(labels)
    return if labels.empty?

    labels = @conversation.label_list - labels
    @conversation.update(label_list: labels)
  end

  def assign_team(team_ids = [])
    # Keep nil/0 handling for existing automation and macro payloads.
    should_unassign = team_ids.blank? || %w[nil 0].include?(team_ids[0].to_s)
    if should_unassign
      return Conversations::TeamAssignmentService.new(conversation: @conversation, team_id: nil).perform
    end

    # check if team belongs to account only if team_id is present
    # if team_id is nil, then it means that the team is being unassigned
    return unless !team_ids[0].nil? && team_belongs_to_account?(team_ids)

    Conversations::TeamAssignmentService.new(
      conversation: @conversation,
      team_id: team_ids[0]
    ).perform
  end

  def remove_assigned_agent(_params)
    Conversations::AssignmentService.new(conversation: @conversation, assignee_id: nil).perform
  end

  def remove_assigned_team(_params)
    Conversations::TeamAssignmentService.new(conversation: @conversation, team_id: nil).perform
  end

  def send_email_transcript(emails)
    return unless @account.email_transcript_enabled?

    emails = emails[0].gsub(/\s+/, '').split(',')

    emails.each do |email|
      break unless @account.within_email_rate_limit?

      email = parse_email_variables(@conversation, email)
      ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, email)&.deliver_later
      @account.increment_email_sent_count
    end
  end

  def update_contact_custom_attribute(params)
    attribute_key, value = extract_custom_attribute_params(params)
    if attribute_key.blank?
      Rails.logger.warn("[Automation] update_contact_custom_attribute skipped: blank attribute_key params=#{params.inspect}")
      return
    end

    write_custom_attribute(@conversation.contact, 'contact', attribute_key, value)
  end

  def update_conversation_custom_attribute(params)
    attribute_key, value = extract_custom_attribute_params(params)
    return if attribute_key.blank?

    write_custom_attribute(@conversation, 'conversation', attribute_key, value)
  end

  MAX_DELIVERY_DELAY_SECONDS = 25

  def normalize_delivery(delivery)
    delivery = (delivery || {}).with_indifferent_access
    delay = delivery[:delay_seconds].to_i.clamp(0, MAX_DELIVERY_DELAY_SECONDS)
    mark = ActiveModel::Type::Boolean.new.cast(delivery[:mark_read_and_typing]) && delay.positive?
    { delay_seconds: delay, mark_read_and_typing: mark }
  end

  def schedule_or_send_outbound(delivery:, content: nil, blob_ids: nil, user: nil, automation_rule_id: nil,
                                automation_rule_name: nil, message_source_attrs: nil)
    opts = normalize_delivery(delivery)
    source_attrs = message_source_attrs.presence ||
                   legacy_automation_source(automation_rule_id, automation_rule_name)
    if opts[:delay_seconds].positive?
      if opts[:mark_read_and_typing]
        Whatsapp::MarkReadTypingService.new(conversation: @conversation, force: true).perform
      end

      Messages::DeferredOutboundJob.set(wait: opts[:delay_seconds].seconds).perform_later(
        conversation_id: @conversation.id,
        content: content,
        blob_ids: blob_ids,
        user_id: user&.id,
        message_source_attrs: source_attrs
      )
    else
      yield
    end
  end

  def attachment_message_params(blobs)
    blobs.each { |blob| normalize_blob_audio_content_type!(blob) }

    whatsapp = @conversation.inbox.whatsapp?
    {
      content: nil,
      private: false,
      attachments: blobs,
      is_voice_message: whatsapp && blobs.any? { |blob| voice_note_blob?(blob) },
      force_audio_as_file: !whatsapp
    }
  end

  private

  # A guard blocking this status change is invisible otherwise — the caller
  # (automation, macro, or flow step) just silently fails to do what it was
  # supposed to, and the actual reason lands only in the exception tracker,
  # which nobody running the account ever sees. Leaves a private note on the
  # conversation itself instead, where whoever works it next actually looks.
  #
  # Only fires when enforces_business_rules is on for that specific
  # automation (see Conversations::BusinessRulesGuard#automation_exempt?) —
  # every existing automation keeps its silent-exemption behavior unless an
  # admin turns this on deliberately.
  def record_business_rule_block!(exception)
    return unless exception.record == @conversation

    reason = Array(exception.record.errors[:status]).first
    return if reason.blank?

    # Conversations::SystemAuditNote already skips tweets and re-applies
    # content_attributes after MessageBuilder would otherwise drop them
    # whenever automation_rule_id is present (which ours always is) — reuse
    # it rather than re-derive that the hard way.
    Conversations::SystemAuditNote.perform(
      conversation: @conversation,
      content: business_rule_block_note(reason),
      content_attributes: business_rule_block_source_attributes
    )
  end

  def business_rule_block_note(reason)
    locale = @account.locale.presence || I18n.default_locale
    I18n.with_locale(locale) do
      I18n.t(
        'business_rules.blocked_automation.note',
        source: business_rule_block_source_description,
        reason: business_rule_block_reason_text(reason)
      )
    end
  end

  def business_rule_block_source_description
    case Current.executed_by
    when AutomationRule
      I18n.t('business_rules.blocked_automation.source.automation', name: Current.executed_by.name)
    when Macro
      I18n.t('business_rules.blocked_automation.source.macro', name: Current.executed_by.name)
    else
      I18n.t('business_rules.blocked_automation.source.generic')
    end
  end

  def business_rule_block_source_attributes
    case Current.executed_by
    when AutomationRule
      MessageSourceAttributes.for_automation(Current.executed_by)
    when Macro
      MessageSourceAttributes.for_macro(Current.executed_by)
    else
      {}
    end
  end

  # Mirrors app/javascript/dashboard/composables/useFormatBusinessRuleError.js
  # (the human-facing version of the same codes) so an automation blocked by
  # the same guard reads with the same meaning, just as a note instead of a
  # toast. The attribute_key in these codes doesn't say which model it
  # belongs to (Conversation#business_rule_error_message drops that too), so
  # the display-name lookup checks both rather than guessing wrong.
  def business_rule_block_reason_text(reason)
    if (match = reason.match(/missing_attribute:(\S+)/))
      I18n.t('business_rules.blocked_automation.reasons.missing_attribute', name: business_rule_attribute_name(match[1]))
    elsif (match = reason.match(/missing_reason_attribute:(\S+)/))
      I18n.t('business_rules.blocked_automation.reasons.missing_reason_attribute', name: business_rule_attribute_name(match[1]))
    elsif reason.include?('missing_private_note')
      I18n.t('business_rules.blocked_automation.reasons.missing_private_note')
    elsif (match = reason.match(/forbidden_label:(\S+)/))
      I18n.t('business_rules.blocked_automation.reasons.forbidden_label', label: match[1])
    elsif reason.include?('missing_assignee')
      I18n.t('business_rules.blocked_automation.reasons.missing_assignee')
    else
      I18n.t('business_rules.blocked_automation.reasons.generic')
    end
  end

  def business_rule_attribute_name(key)
    definition = @account.custom_attribute_definitions.find_by(attribute_key: key, attribute_model: :conversation_attribute) ||
                 @account.custom_attribute_definitions.find_by(attribute_key: key, attribute_model: :contact_attribute)
    definition&.attribute_display_name || key
  end

  def legacy_automation_source(automation_rule_id, automation_rule_name)
    return if automation_rule_id.blank?

    MessageSourceAttributes.payload('automation', automation_rule_id, automation_rule_name).merge(
      automation_rule_id: automation_rule_id,
      automation_rule_name: automation_rule_name
    )
  end

  def extract_custom_attribute_params(params)
    data = params.is_a?(Array) ? params[0] : params
    return [nil, nil] if data.blank?

    data = data.with_indifferent_access if data.respond_to?(:with_indifferent_access)
    [data[:attribute_key].to_s, data[:value]]
  end

  def write_custom_attribute(record, scope, key, raw_value)
    writer = Variables::Writer.new(account: @account)
    target = "#{scope}.custom_attribute.#{key}"
    return unless writer.target(target, context: 'automation')

    definition = @account.custom_attribute_definitions.find_by!(attribute_key: key, attribute_model: "#{scope}_attribute")
    value = Variables::ValueNormalizer.new(drops: variable_drops).normalize(definition, raw_value)
    record.update!(writer.attributes(record: record, target: target, value: value, context: 'automation'))
  end

  def variable_drops
    Variables::ContextFactory.new(account: @account, records: { conversation: @conversation }).build(surface: 'automation')
  end

  def last_responding_agent_id
    @conversation.messages.outgoing.where(sender_type: 'User', private: false).last&.sender_id
  end

  def agent_belongs_to_inbox?(agent_ids)
    member_ids = @conversation.inbox.members.pluck(:user_id)
    assignable_agent_ids = member_ids + @account.administrators.ids

    assignable_agent_ids.include?(agent_ids[0])
  end

  def team_belongs_to_account?(team_ids)
    @account.team_ids.include?(team_ids[0])
  end

  def conversation_a_tweet?
    return false if @conversation.additional_attributes.blank?

    @conversation.additional_attributes['type'] == 'tweet'
  end

  def normalize_blob_audio_content_type!(blob)
    resolved = resolve_audio_content_type(blob.content_type, blob.filename.to_s)
    return if resolved.blank? || resolved == blob.content_type

    blob.update!(content_type: resolved)
  end

  def voice_note_blob?(blob)
    voice_note_content_type?(blob.content_type)
  end
end

ActionService.include_mod_with('ActionService')
