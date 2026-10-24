class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform(record_run: true)
    @run_details = { actions: [] }
    @rule.actions.each_with_index { |action, index| perform_action(action, index) }
    self.record_run if record_run
  ensure
    Current.reset
  end

  def record_run(outcome: 'executed', reason: nil)
    if @run_details[:actions].any? { |action| action[:outcome] == 'error' }
      outcome = 'failed'
      reason = 'action_error'
    end
    AutomationRules::RunRecorder.record(rule: @rule, conversation: @conversation, outcome: outcome, reason: reason, details: @run_details)
  end

  private

  def perform_action(action, index)
    @conversation.reload
    action = action.with_indifferent_access
    begin
      result = execute_action(action)
      @run_details[:actions] << { name: action[:action_name], outcome: 'ok' }
      @run_details[:message_id] = result.id if result.is_a?(Message) && result.persisted?
    rescue StandardError => e
      @run_details[:actions] << { name: action[:action_name], outcome: 'error', index: index, error_class: e.class.name }
      ChatwootExceptionTracker.new(e, account: @account).capture_exception
    end
  end

  def automation_message_attributes
    MessageSourceAttributes.for_automation(@rule)
  end

  def execute_action(action)
    name = action[:action_name].to_s
    if %w[send_message send_attachment].include?(name)
      send(name, action[:action_params], action[:delivery])
    else
      send(name, action[:action_params])
    end
  end

  def send_attachment(blob_ids, delivery = nil)
    return if conversation_a_tweet?
    return skip_outbound_outside_messaging_window! unless @conversation.can_reply?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)
    return if blobs.blank?

    schedule_or_send_outbound(
      delivery: delivery,
      blob_ids: blobs.map(&:id),
      message_source_attrs: automation_message_attributes
    ) do
      params = attachment_message_params(blobs).merge(
        content_attributes: automation_message_attributes
      )
      Messages::MessageBuilder.new(nil, @conversation, params).perform
    end
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_whatsapp_template(params)
    template_params = extract_whatsapp_template_params(params)
    return skip_whatsapp_template!(:template_missing) if template_params.blank?

    inbox = @conversation.inbox
    return skip_whatsapp_template!(:not_whatsapp) unless inbox.whatsapp?
    return skip_whatsapp_template!(:wrong_inbox) unless inbox.id.to_i == template_params[:inbox_id].to_i

    template = find_approved_whatsapp_template(inbox.channel, template_params)
    return skip_whatsapp_template!(:template_missing) if template.blank?

    interpolated = interpolate_whatsapp_template_params(template_params)

    payload = interpolated.slice(:name, :namespace, :language, :category, :processed_params)
    Messages::MessageBuilder.new(nil, @conversation, {
                                   content: rendered_whatsapp_template_body(template, payload[:processed_params]),
                                   private: false,
                                   template_params: payload,
                                   content_attributes: automation_message_attributes
                                 }).perform(variables_resolved: true)
  rescue Variables::DeliveryRenderer::Error => e
    skip_unresolved_whatsapp_template!(e)
  end

  def skip_unresolved_whatsapp_template!(error)
    leave_automation_skip_note!(
      'automation.template_skipped.variables',
      { whatsapp_template_skipped: error.status, variable_resolution: error.message },
      reason: error.message
    )
  end

  def send_message(message, delivery = nil)
    return if conversation_a_tweet?
    return skip_outbound_outside_messaging_window! unless @conversation.can_reply?

    content = message.is_a?(Array) ? message[0] : message
    schedule_or_send_outbound(
      delivery: delivery,
      content: content,
      message_source_attrs: automation_message_attributes
    ) do
      params = {
        content: content,
        private: false,
        content_attributes: automation_message_attributes
      }
      Messages::MessageBuilder.new(nil, @conversation, params).perform
    end
  end

  def skip_outbound_outside_messaging_window!
    leave_automation_skip_note!(
      'automation.message_skipped_messaging_window',
      { messaging_window_skipped: true }
    )
  end

  def skip_whatsapp_template!(reason)
    leave_automation_skip_note!(
      "automation.template_skipped.#{reason}",
      { whatsapp_template_skipped: reason.to_s }
    )
  end

  def leave_automation_skip_note!(i18n_key, extra_attrs, **interpolations)
    locale = @account.locale.presence || I18n.default_locale
    content = I18n.with_locale(locale) { I18n.t(i18n_key, name: @rule.name, **interpolations) }

    Conversations::SystemAuditNote.perform(
      conversation: @conversation,
      content: content,
      content_attributes: extra_attrs.merge(automation_rule_id: @rule.id)
    )
  end

  def extract_whatsapp_template_params(params)
    data = params.is_a?(Array) ? params[0] : params
    return {} if data.blank?

    data.respond_to?(:with_indifferent_access) ? data.with_indifferent_access : {}
  end

  def find_approved_whatsapp_template(channel, template_params)
    Array(channel.message_templates).find do |entry|
      entry['name'] == template_params[:name] &&
        entry['language']&.downcase == template_params[:language].to_s.downcase &&
        entry['status']&.downcase == 'approved'
    end
  end

  def interpolate_whatsapp_template_params(template_params)
    copy = template_params.deep_dup
    processed = copy[:processed_params]
    return copy if processed.blank?

    drops = Variables::ContextFactory.new(account: @account, records: { conversation: @conversation }).build(surface: 'automation')
    rendered = Variables::DeliveryRenderer.new(drops: drops).render(processed, path: 'processed_params')
    copy.merge(processed_params: rendered)
  end

  def rendered_whatsapp_template_body(template, processed_params)
    body = Array(template['components']).find { |component| component['type'].to_s.casecmp('BODY').zero? }
    text = body&.[]('text').presence || template['name']
    values = (processed_params || {}).with_indifferent_access
    body_values = (values[:body] || values).with_indifferent_access
    text.gsub(/\{\{\s*([^}]+)\s*\}\}/) do
      body_values[Regexp.last_match(1).strip].presence || "{{#{Regexp.last_match(1).strip}}}"
    end
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = {
      content: message[0],
      private: true,
      content_attributes: automation_message_attributes
    }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  def notify_assignee(_params = nil)
    return if @conversation.assignee.blank?

    NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: @conversation.assignee,
      account: @account,
      primary_actor: @conversation,
      secondary_actor: nil
    ).perform
  end

  # Run a saved macro's actions on this conversation (one level deep — no nested execute_macro).
  def execute_macro(macro_ids)
    return if @executing_macro

    macro_id = Array(macro_ids).first
    return if macro_id.blank?

    macro = @account.macros.find_by(id: macro_id)
    return if macro.blank?

    user = macro.created_by || @account.administrators.order(:id).first || @account.users.order(:id).first
    return if user.blank?

    @executing_macro = true
    Macros::ExecutionService.new(macro, @conversation, user).perform
  ensure
    @executing_macro = false
  end

  def enter_flow(flow_refs)
    return unless @account.feature_enabled?('flows_v1')
    return if @conversation.in_flow?

    ref = Array(flow_refs).first
    return if ref.blank?

    flow = @account.flows.active.find_by(id: ref) || @account.flows.active.find_by(name: ref.to_s)
    return if flow.blank?
    return if @conversation.flow_already_entered?(flow.id)

    Flows::StartService.new(
      account: @account,
      conversation: @conversation,
      flow: flow,
      trigger: 'automation_rule'
    ).perform
  end
end
