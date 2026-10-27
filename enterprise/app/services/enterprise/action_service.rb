module Enterprise::ActionService
  def assign_captain(selector)
    assistant = @conversation.inbox.captain_assistant if @account.feature_enabled?('captain_integration')
    reason = captain_assignment_block_reason(selector, assistant)
    return record_captain_assignment_skip(reason) if reason

    @conversation.with_lock do
      return if @conversation.pending? && @conversation.ai_assignee == assistant

      # An explicit assignment bypasses audience and response hours, just like manual assignment.
      Conversations::AssignmentService.new(
        conversation: @conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant'
      ).perform
    end
    record_captain_assignment(assistant)
  end

  def add_sla(sla_policy_id)
    return if sla_policy_id.blank?
    # SLA is a premium feature; automation rules must not keep applying SLAs once it is disabled.
    return unless @account.feature_enabled?('sla')

    sla_policy = @account.sla_policies.find_by(id: sla_policy_id.first)
    return if sla_policy.nil?
    return if @conversation.sla_policy.present?
    return unless @conversation.sla_applicable?

    Rails.logger.info "SLA:: Adding SLA #{sla_policy.id} to conversation: #{@conversation.id}"
    @conversation.update!(sla_policy_id: sla_policy.id)
  end

  private

  def captain_assignment_block_reason(selector, assistant)
    return :disabled unless @account.feature_enabled?('captain_integration')
    return :disconnected unless assistant
    return :different if selector != 'captain' && selector != "captain:#{assistant.id}"
    return :external_bot if @conversation.inbox.external_bot_active?

    assistant.paused_reason
  end

  def captain_assignment_source
    business_rule_block_source_attributes
  end

  def record_captain_assignment(assistant)
    content = I18n.t('captain.assignment.assigned', name: assistant.name, locale: @account.locale)
    Conversations::SystemAuditNote.perform(conversation: @conversation, content: content, content_attributes: captain_assignment_source)
  end

  def record_captain_assignment_skip(reason)
    content = I18n.t('captain.assignment.skipped', locale: @account.locale).fetch(reason)
    source = captain_assignment_source
    Conversations::SystemAuditNote.perform(conversation: @conversation, content: content, content_attributes: source)
  end
end
