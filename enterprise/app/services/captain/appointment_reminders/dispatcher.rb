# Sends the reminders that are due. Runs every minute from Calendar::AppointmentRemindersJob.
class Captain::AppointmentReminders::Dispatcher
  BATCH_SIZE = 200

  def perform
    Captain::AppointmentReminder.due.order(:scheduled_at).limit(BATCH_SIZE).each { |reminder| dispatch(reminder) }
  end

  private

  # Sender locks event then reminder, the same order as reconciliation and its callbacks.
  def dispatch(reminder)
    Captain::AppointmentReminders::Sender.new(reminder).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: reminder.account).capture_exception
    Captain::AppointmentReminder.where(id: reminder.id, status: 'pending')
                                .update_all(status: 'skipped', skipped_reason: 'error', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
