# Claims and creates one asynchronous template message per appointment. The event row lock serializes workers
# and moves/cancellations; Delivery completes the claim only after Meta accepts the message.
class Calendar::CustomerReminders::Dispatcher
  LOOKAHEAD = 36.hours

  def initialize(now: Time.current)
    @now = now
  end

  def perform
    CalendarEvent.customer_reminder_pending.where(start_at: @now..(@now + LOOKAHEAD)).includes(:account).find_each do |event|
      dispatch(event)
    end
  end

  private

  def dispatch(event)
    event.with_lock do
      next unless eligible?(event)
      next if skip(event)
      next unless Calendar::CustomerReminders::Schedule.due_at(event) <= @now
      next unless Calendar::CustomerReminders::Schedule.sending_hours?(event.account, @now)

      enqueue(event)
    end
  rescue StandardError => e
    Rails.logger.error("Calendar customer reminder dispatch failed for event #{event.id}: #{e.class}")
  end

  def eligible?(event)
    event.account.reload.customer_reminders_enabled == true && !event.ai_booked? && !event.bot_followup_enabled? &&
      !event.discarded? && event.start_at > @now && event.conversation.present? &&
      unclaimed?(event)
  end

  def unclaimed?(event)
    event.customer_reminder_sent_at.nil? && CalendarEvent::CUSTOMER_REMINDER_PENDING_STATUSES.include?(event.customer_reminder_status)
  end

  def skip(event)
    reason = if event.appointment_status == 'confirmed'
               'skipped_confirmed'
             elsif event.start_at < scheduled_at(event) + CalendarEvent::CUSTOMER_REMINDER_LEAD_TIME
               'skipped_too_close'
             elsif !notice(event).whatsapp_cloud?
               'skipped_channel'
             end
    event.update!(customer_reminder_status: reason) if reason
    reason
  end

  def scheduled_at(event)
    event.activities.where("details ? 'start_at'").where(action: %w[updated moved_in_google]).maximum(:created_at) || event.created_at
  end

  def notice(event)
    Integrations::GoogleCalendar::CustomerNotice.new(
      conversation: event.conversation, record: event, timezone: Integrations::GoogleCalendar::Timezone.for(event.account).name,
      template_name: Calendar::ActivationKit::REMINDER_TEMPLATE_NAME
    )
  end

  def enqueue(event)
    customer_notice = notice(event)
    return no_template(event) unless customer_notice.template

    cap = Automations::ProactiveSendCap.new(event.account)
    return unless cap.reserve!

    begin
      create_message(event, customer_notice)
    rescue StandardError => e
      cap.release!
      record_failure(event, e)
    end
  end

  def create_message(event, customer_notice)
    attempt = event.customer_reminder_status.to_s.delete_prefix('retry_').to_i + 1
    # The transaction also rolls back the claim if creating the message fails.
    event.class.transaction(requires_new: true) do
      event.update!(customer_reminder_status: "queued_#{attempt}")
      customer_notice.deliver!(additional_attributes: {
                                 'customer_reminder' => { 'start_at' => event.start_at.iso8601(6), 'attempt' => attempt,
                                                          'cap_date' => Time.zone.today.iso8601 }
                               })
    end
  end

  def record_failure(event, error)
    attempt = event.reload.customer_reminder_status.to_s.delete_prefix('retry_').to_i + 1
    event.update!(customer_reminder_status: attempt >= 3 ? 'skipped_error' : "retry_#{attempt}")
    Rails.logger.error("Calendar customer reminder creation failed for event #{event.id}: #{error.class}")
  end

  def no_template(event)
    event.update!(customer_reminder_status: 'no_template') if event.customer_reminder_status.nil?
    notes = event.conversation.messages.activity.where("additional_attributes ->> 'calendar_reminder_missing' = ?", event.id.to_s)
    return if notes.exists?

    event.conversation.messages.create!(
      account_id: event.account_id, inbox_id: event.conversation.inbox_id, message_type: :activity,
      additional_attributes: { 'calendar_reminder_missing' => event.id },
      content: I18n.t('conversations.activity.calendar.reminder_notice_not_sent',
                      locale: event.account.locale, event_title: event.summary)
    )
  end
end
