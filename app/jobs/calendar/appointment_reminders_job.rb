# Runs every minute (config/schedule.yml). The community edition has nothing to send; the enterprise
# module sends the reminders of appointments booked by Captain.
class Calendar::AppointmentRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform; end
end

Calendar::AppointmentRemindersJob.prepend_mod_with('Calendar::AppointmentRemindersJob')
