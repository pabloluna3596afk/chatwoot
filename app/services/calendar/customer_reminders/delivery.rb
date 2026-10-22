# Runs through SendReplyJob, where provider errors actually happen. Retrying the cron never duplicates a queued
# message; failed attempts release the daily reservation and allow at most three attempts per scheduled start.
class Calendar::CustomerReminders::Delivery
  def initialize(message)
    @message = message
    @metadata = message.additional_attributes.fetch('customer_reminder')
  end

  def perform
    event.with_lock do
      @message.reload
      next if @message.additional_attributes['customer_reminder_processed']
      next cancel unless current_claim? && eligible?
      next cancel unless @metadata.fetch('cap_date') == Time.zone.today.iso8601
      next cancel unless Calendar::CustomerReminders::Schedule.sending_hours?(event.account, Time.current)

      deliver
    end
  end

  private

  def event
    @event ||= @message.account.calendar_events.where(conversation_id: @message.conversation_id)
                       .find(@message.additional_attributes.fetch('calendar_event_id'))
  end

  def current_claim?
    event.start_at.iso8601(6) == @metadata.fetch('start_at') && event.customer_reminder_status == "queued_#{attempt}"
  end

  def eligible?
    event.account.reload.customer_reminders_enabled == true && !event.discarded? && event.start_at > Time.current &&
      event.appointment_status != 'confirmed' && !event.ai_booked? && !event.bot_followup_enabled?
  end

  def attempt
    @metadata.fetch('attempt')
  end

  def cap
    @cap ||= Automations::ProactiveSendCap.new(event.account, date: Date.iso8601(@metadata.fetch('cap_date')))
  end

  def deliver
    return fail_attempt unless send_message

    event.update!(customer_reminder_status: 'sent', customer_reminder_sent_at: Time.current)
    processed!
  end

  def send_message
    return true if @message.source_id.present?

    Whatsapp::SendOnWhatsappService.new(message: @message).perform
    @message.reload.source_id.present? && !@message.failed?
  rescue StandardError => e
    Rails.logger.error("Calendar customer reminder delivery failed for event #{event.id}: #{e.class}")
    false
  end

  def fail_attempt
    Rails.logger.warn("Calendar customer reminder attempt #{attempt} failed for event #{event.id}")
    cap.release!
    event.update!(customer_reminder_status: attempt >= 3 ? 'skipped_error' : "retry_#{attempt}")
    @message.update!(status: :failed)
    processed!
  end

  def cancel
    cap.release!
    event.update!(customer_reminder_status: attempt == 1 ? nil : "retry_#{attempt - 1}") if current_claim?
    @message.update!(status: :failed)
    processed!
  end

  def processed!
    @message.update!(additional_attributes: @message.additional_attributes.merge('customer_reminder_processed' => true))
  end
end
