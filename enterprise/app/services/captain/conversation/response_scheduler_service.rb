class Captain::Conversation::ResponseSchedulerService
  MAX_ATTACHMENT_WAIT_SECONDS = 4

  def initialize(message:)
    @message = message
    @conversation = message.conversation
    @assistant = message.inbox.captain_assistant
  end

  def perform
    return unless reserve_response_slot

    wait_time = [@assistant.reply_delay_seconds.seconds, attachment_wait_time].max
    return Captain::Conversation::ResponseBuilderJob.perform_later(*job_args) if wait_time.zero?

    Captain::Conversation::ResponseBuilderJob.set(wait: wait_time).perform_later(*job_args)
  end

  private

  def reserve_response_slot
    @conversation.reload.with_lock do
      scheduled_message_id = @conversation.additional_attributes['captain_scheduled_response_message_id'].to_i
      next false if scheduled_message_id >= @message.id

      @conversation.update!(additional_attributes: @conversation.additional_attributes.merge(
        'captain_scheduled_response_message_id' => @message.id
      ))
      true
    end
  end

  def job_args
    [@conversation, @assistant, @message.id]
  end

  def captain_v2_enabled?
    @conversation.account.feature_enabled?('captain_integration_v2')
  end

  def attachment_wait_time
    attachment_count = captain_v2_enabled? ? recent_attachment_count : @message.attachments.size
    return 0.seconds if attachment_count.zero?

    base_wait = 1.second
    additional_wait = [attachment_count, MAX_ATTACHMENT_WAIT_SECONDS].min.seconds
    base_wait + additional_wait
  end

  def recent_attachment_count
    maximum_wait = (MAX_ATTACHMENT_WAIT_SECONDS + 1).seconds

    @conversation.messages.incoming
                 .joins(:attachments)
                 .where(attachments: { created_at: maximum_wait.ago.. })
                 .count
  end
end
