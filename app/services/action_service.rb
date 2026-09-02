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

  def snooze_conversation(_params)
    @conversation.snoozed!
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

    definition = find_writable_custom_attribute(attribute_key, :contact_attribute)
    if definition.blank?
      Rails.logger.warn("[Automation] update_contact_custom_attribute skipped: no contact attribute '#{attribute_key}' on account #{@account.id}")
      return
    end
    if definition.formula?
      Rails.logger.warn("[Automation] update_contact_custom_attribute skipped: '#{attribute_key}' is a formula attribute")
      return
    end

    contact = @conversation.contact
    attrs = (contact.custom_attributes || {}).merge(
      attribute_key => normalize_custom_attribute_value(definition, value)
    )
    contact.update!(custom_attributes: attrs)
  end

  def update_conversation_custom_attribute(params)
    attribute_key, value = extract_custom_attribute_params(params)
    if attribute_key.blank?
      Rails.logger.warn("[Automation] update_conversation_custom_attribute skipped: blank attribute_key params=#{params.inspect}")
      return
    end

    definition = find_writable_custom_attribute(attribute_key, :conversation_attribute)
    if definition.blank?
      Rails.logger.warn("[Automation] update_conversation_custom_attribute skipped: no conversation attribute '#{attribute_key}' on account #{@account.id}")
      return
    end
    if definition.formula?
      Rails.logger.warn("[Automation] update_conversation_custom_attribute skipped: '#{attribute_key}' is a formula attribute")
      return
    end

    attrs = (@conversation.custom_attributes || {}).merge(
      attribute_key => normalize_custom_attribute_value(definition, value)
    )
    @conversation.update!(custom_attributes: attrs)
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

  def find_writable_custom_attribute(attribute_key, attribute_model)
    @account.custom_attribute_definitions.find_by(
      attribute_key: attribute_key,
      attribute_model: attribute_model
    )
  end

  def normalize_custom_attribute_value(definition, raw_value)
    return Array.wrap(raw_value).map(&:to_s) if definition.attribute_display_type == 'multi_list'

    rendered = render_custom_attribute_template(raw_value)

    case definition.attribute_display_type
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
  rescue ArgumentError, TypeError => e
    Rails.logger.warn("[Automation] custom attribute normalize failed for #{definition.attribute_key}: #{e.message}")
    # Do not persist garbage into typed date/number fields.
    raise if %w[date datetime number currency percent].include?(definition.attribute_display_type)

    raw_value.to_s
  end

  def render_custom_attribute_template(raw_value)
    text = raw_value.to_s
    return text unless text.include?('{{')

    AutomationRules::MessageRendererService.new(@conversation, text).perform
  end

  def parse_custom_attribute_date(rendered)
    return rendered.iso8601 if rendered.is_a?(Date)
    return rendered.to_date.iso8601 if rendered.is_a?(Time) || rendered.is_a?(DateTime)

    text = rendered.to_s.strip
    # Native date inputs and Liquid relative dates resolve to ISO YYYY-MM-DD:
    # {{ date.today }}, {{ date.today | plus_days: N }}, {{ date.today | minus_days: N }}.
    if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      return Date.iso8601(text).iso8601
    end

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
