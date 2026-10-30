module Captain::Copilot::ReplySuggestionUsage
  private

  def reserve_copilot_usage
    @usage_reservation_id = SecureRandom.uuid
    unless @account.reserve_captain_ai_usage!(bucket: :copilot, reservation_id: @usage_reservation_id)
      @usage_reservation_id = nil
      return false
    end

    true
  end

  def close_copilot_usage
    return unless @usage_reservation_id

    method = @credit_used ? :finish_captain_ai_usage! : :release_captain_ai_usage!
    @account.public_send(method, bucket: :copilot, reservation_id: @usage_reservation_id)
  end

  def generate_metered_response(conversation, target_message)
    return persist_discarded_response unless target_message&.incoming?
    return copilot_limit_response unless reserve_copilot_usage

    response, runner = generate_metered_reply(conversation, target_message)
    raise Captain::Copilot::ReplySuggestionService::GenerationError, response['reasoning'] if response['error']

    persist_response(response, runner, conversation, target_message)
  end

  def copilot_limit_response
    reset_date = @account.current_usage_period.period_end.to_date
    { error: I18n.t('captain.copilot_limit', reset_date: reset_date), error_code: 429 }
  end

  def generate_metered_reply(conversation, target_message)
    Llm::UsageContext.with(
      account: @account,
      bucket: :copilot,
      feature: 'copilot_reply_suggestion',
      context: { conversation_id: conversation.id, message_id: target_message.id, reservation_required: true, required_gate: 'captain_integration' },
      reservation_id: @usage_reservation_id
    ) { generate_reply(conversation) }
  end
end
