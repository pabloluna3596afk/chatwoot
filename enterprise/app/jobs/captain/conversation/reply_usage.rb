module Captain::Conversation::ReplyUsage
  private

  def reserve_reply_usage!
    @reply_reservation_id = "captain-reply-#{@conversation.id}-#{SecureRandom.uuid}"
    return true if account.reserve_captain_ai_usage!(bucket: :captain_responses, reservation_id: @reply_reservation_id)

    @reply_reservation_id = nil
    false
  end

  def finish_reply_usage!
    return unless @reply_reservation_id

    account.finish_captain_ai_usage!(bucket: :captain_responses, reservation_id: @reply_reservation_id)
  end

  def release_reply_usage!
    return unless @reply_reservation_id

    # The ID stays available until the delivery transaction commits, so ensure
    # can refund the reservation if delivery rolls back after finishing it.
    account.release_captain_ai_usage!(bucket: :captain_responses, reservation_id: @reply_reservation_id)
    @reply_reservation_id = nil
  end

  def process_usage_exhausted
    Captain::Conversation::UsageLimitHandoff.new(conversation: @conversation).perform
  end

  def with_reply_usage(feature:, &)
    return yield unless @reply_reservation_id

    Llm::UsageContext.with(
      account: account, bucket: :captain_responses, feature: feature, reservation_id: @reply_reservation_id,
      context: { conversation_id: @conversation.id, message_id: @responding_to_message_id }, &
    )
  end
end
