# Runs every minute; enterprise calls super before dispatching Captain reminders.
class Calendar::AppointmentRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Calendar::CustomerReminders::Dispatcher.new.perform
  end
end

Calendar::AppointmentRemindersJob.prepend_mod_with('Calendar::AppointmentRemindersJob')
