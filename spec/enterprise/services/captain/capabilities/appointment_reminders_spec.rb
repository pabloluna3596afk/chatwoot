require 'rails_helper'

RSpec.describe Captain::Capabilities::AppointmentReminders do
  let(:inbox) { instance_double(Inbox) }
  let(:appointments) { instance_double(Captain::AppointmentsSettings, any_reminder_enabled?: reminders_enabled) }
  let(:assistant) { instance_double(Captain::Assistant, appointments: appointments) }
  let(:reminders_enabled) { true }
  let(:ready_booking) { { status: 'ready', reason: nil } }

  before do
    allow(Captain::Capabilities::Booking).to receive(:new).and_return(instance_double(Captain::Capabilities::Booking, call: ready_booking))
  end

  it 'inherits the booking status and reason when booking is not ready' do
    allow(Captain::Capabilities::Booking).to receive(:new).and_return(
      instance_double(Captain::Capabilities::Booking, call: { status: 'needs_setup', reason: 'no_calendar_selected' })
    )
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'no_calendar_selected', count: nil)
  end

  it 'returns off when every reminder is disabled' do
    allow(appointments).to receive(:any_reminder_enabled?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'disabled', count: nil)
  end

  it 'marks reminders that require templates outside the reply window as ready with a note' do
    readiness = instance_double(Captain::AppointmentReminders::Readiness, outside_window_reason: 'not_sent_window')
    allow(Captain::AppointmentReminders::Readiness).to receive(:new).and_return(readiness)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'ready', reason: 'window_only', count: nil)
  end

  it 'returns ready without a reason when no template is required' do
    readiness = instance_double(Captain::AppointmentReminders::Readiness, outside_window_reason: nil)
    allow(Captain::AppointmentReminders::Readiness).to receive(:new).and_return(readiness)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'ready', reason: nil, count: nil)
  end
end
