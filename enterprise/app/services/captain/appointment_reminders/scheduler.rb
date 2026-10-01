# Creates, moves and drops the reminder rows of an appointment booked by Captain. Nothing is sent here:
# Captain::AppointmentReminders::Dispatcher sends what is due, a minute at a time.
class Captain::AppointmentReminders::Scheduler
  class << self
    # One row per enabled reminder kind. Calling it again for the same event creates nothing new, so a
    # retried booking never schedules (and so never sends) a reminder twice.
    def schedule(event, assistant:, conversation:)
      return if event.start_at.blank?

      settings = assistant.appointments
      Captain::AppointmentReminder::KINDS.each do |kind|
        next unless settings.public_send("#{kind}?")

        create_reminder(event, assistant, conversation, kind)
      end
    end

    # The appointment moved: every reminder gets its new time, including ones already sent for the old one.
    def reschedule(event)
      return if event.start_at.blank?

      event.appointment_reminders.where.not(status: 'cancelled').find_each do |reminder|
        scheduled_at = event.start_at - reminder.lead_time
        reminder.update!(scheduled_at: scheduled_at, sent_at: nil, **initial_state(scheduled_at))
      end
    end

    # The appointment was cancelled: what is still waiting is dropped.
    def cancel(event)
      event.appointment_reminders.pending.update_all(status: 'cancelled', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def create_reminder(event, assistant, conversation, kind)
      scheduled_at = event.start_at - Captain::AppointmentReminder::LEAD_TIMES.fetch(kind)
      Captain::AppointmentReminder.create!(
        account_id: event.account_id, calendar_event_id: event.id, captain_assistant_id: assistant.id,
        conversation_id: conversation.id, kind: kind, scheduled_at: scheduled_at, **initial_state(scheduled_at)
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    # A reminder whose time already passed (the booking is closer than its lead time) is not sent.
    def initial_state(scheduled_at)
      return { status: 'pending', skipped_reason: nil } if scheduled_at > Time.current

      { status: 'skipped', skipped_reason: 'too_close' }
    end
  end
end
