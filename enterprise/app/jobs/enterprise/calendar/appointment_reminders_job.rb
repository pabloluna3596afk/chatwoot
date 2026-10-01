module Enterprise::Calendar::AppointmentRemindersJob
  def perform
    super

    Captain::AppointmentReminders::Dispatcher.new.perform
  end
end
