# Sends the reminders that are due. Runs every minute from Calendar::AppointmentRemindersJob.
class Captain::AppointmentReminders::Dispatcher
  BATCH_SIZE = 200

  def perform
    Captain::AppointmentReminder.due.order(:scheduled_at).limit(BATCH_SIZE).each { |reminder| dispatch(reminder) }
  end

  private

  # The row lock makes a reminder go out once even if two workers overlap.
  def dispatch(reminder)
    reminder.with_lock do
      next unless reminder.pending?

      Captain::AppointmentReminders::Sender.new(reminder).perform
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: reminder.account).capture_exception
    Captain::AppointmentReminder.where(id: reminder.id, status: 'pending')
                                .update_all(status: 'skipped', skipped_reason: 'error', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
