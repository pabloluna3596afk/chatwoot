module Enterprise::CalendarEvent
  def self.prepended(base)
    base.has_many :appointment_reminders, class_name: 'Captain::AppointmentReminder', dependent: :delete_all
    base.after_update_commit :sync_appointment_reminders
  end

  private

  # Whoever moves or cancels the appointment (the customer through Captain, an agent in the agenda, a change
  # made in Google) keeps its reminders in step. Events without reminders cost one query.
  def sync_appointment_reminders
    return unless appointment_reminders.exists?

    if saved_change_to_deleted_at? && discarded?
      Captain::AppointmentReminders::Scheduler.cancel(self)
    elsif saved_change_to_start_at?
      Captain::AppointmentReminders::Scheduler.reschedule(self)
    end
  end
end
