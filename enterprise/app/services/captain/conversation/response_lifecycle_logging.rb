module Captain::Conversation::ResponseLifecycleLogging
  private

  def conversation_pending?
    @observed_conversation_status, @observed_assignee_id = Conversation.uncached do
      Conversation.where(id: @conversation.id).pick(:status, :assignee_id)
    end
    @observed_conversation_status == 'pending' || @observed_conversation_status == Conversation.statuses[:pending]
  end

  def log_non_pending
    return if @responding_to_message_id.nil?

    Rails.logger.info(
      "[CAPTAIN][ResponseLifecycle] event=job_skipped reason=conversation_not_pending conversation_id=#{@conversation.id} " \
      "responding_to_message_id=#{@responding_to_message_id} conversation_status=#{@observed_conversation_status}"
    )
  end

  def log_human_assignee
    Rails.logger.info("[CAPTAIN][ResponseLifecycle] event=skipped reason=human_assignee conversation_id=#{@conversation.id}")
  end

  def log_pre_generation_discard
    Rails.logger.info(
      '[CAPTAIN][ResponseLifecycle] event=response_discarded reason=newer_customer_message_before_generation ' \
      "conversation_id=#{@conversation.id} responding_to_message_id=#{@responding_to_message_id}"
    )
  end
end
