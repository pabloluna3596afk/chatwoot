require 'rails_helper'

RSpec.describe Calendar::AppointmentRemindersJob do
  it 'runs the community dispatcher on the existing scheduled queue' do
    dispatcher = instance_double(Calendar::CustomerReminders::Dispatcher, perform: nil)
    allow(Calendar::CustomerReminders::Dispatcher).to receive(:new).and_return(dispatcher)
    # The same example also runs when enterprise is loaded, without dispatching real Captain reminders.
    if defined?(Captain::AppointmentReminders::Dispatcher)
      captain = instance_double(Captain::AppointmentReminders::Dispatcher, perform: nil)
      allow(Captain::AppointmentReminders::Dispatcher).to receive(:new).and_return(captain)
    end

    described_class.perform_now

    expect(dispatcher).to have_received(:perform).once
    expect(described_class.queue_name).to eq('scheduled_jobs')
  end
end
