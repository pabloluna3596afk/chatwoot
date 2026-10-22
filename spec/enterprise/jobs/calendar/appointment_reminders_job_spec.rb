require 'rails_helper'

RSpec.describe Calendar::AppointmentRemindersJob do
  it 'keeps enterprise super dispatching community and Captain reminders' do
    customer = instance_double(Calendar::CustomerReminders::Dispatcher, perform: nil)
    captain = instance_double(Captain::AppointmentReminders::Dispatcher, perform: nil)
    allow(Calendar::CustomerReminders::Dispatcher).to receive(:new).and_return(customer)
    allow(Captain::AppointmentReminders::Dispatcher).to receive(:new).and_return(captain)

    described_class.perform_now

    expect(customer).to have_received(:perform).once
    expect(captain).to have_received(:perform).once
  end
end
