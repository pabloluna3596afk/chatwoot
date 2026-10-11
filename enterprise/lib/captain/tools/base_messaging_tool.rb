# Shared behavior of the Captain tools that send a Flow or a template. They only work in a real conversation (a customer
# message is being answered) whose WhatsApp inbox has the owner's switch on, and they never send: they check the
# request, stash it (Captain::Messaging::Intent) and the response job sends it, through Captain::Messaging::SendService,
# instead of the model's text. What is allowed, with what variables and how often is decided by the owner's settings and
# the server, never by the arguments of the model.
class Captain::Tools::BaseMessagingTool < Captain::Tools::BasePublicTool
  private

  # [conversation, nil] or [nil, message for the model].
  def conversation_for(tool_context)
    state = tool_context.state
    return [nil, translate('not_here')] if state[:responding_to_message_id].blank?

    conversation = find_conversation(state)
    return [nil, 'Conversation not found'] unless conversation
    return [nil, translate('errors.disabled')] unless @assistant.messaging_active_in?(conversation.inbox)

    [conversation, nil]
  end

  # Asks the service whether the send would be allowed now (the real check happens again when it is sent) and stashes it.
  def prepare(conversation, tool_context, request)
    request.responding_to_message_id = tool_context.state[:responding_to_message_id]
    outcome = Captain::Messaging::SendService.new(conversation: conversation, assistant: @assistant, request: request).precheck
    return outcome_text(outcome) if outcome
    return translate('already_prepared') unless Captain::Messaging::Intent.stash(conversation, request)

    log_tool_usage(self.class.name.demodulize, conversation_id: conversation.id, kind: request.kind, resource: request.resource_key)
    translate("prepared_#{request.kind}")
  end

  def outcome_text(outcome)
    return translate('already_sent') if outcome.duplicate?

    text = outcome.message
    text += " #{translate('retry_after', minutes: (outcome.retry_after / 60.0).ceil)}" if outcome.retry_after
    text
  end

  def integer_param(value)
    Integer(value.to_s, exception: false)
  end

  def translate(key, **)
    I18n.t("captain.messaging.#{key}", locale: @assistant.account.locale, **)
  end

  def purpose_of(entry)
    entry['purpose'].presence
  end
end
