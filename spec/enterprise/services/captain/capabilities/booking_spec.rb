require 'rails_helper'

RSpec.describe Captain::Capabilities::Booking do
  let(:inbox) { instance_double(Inbox, id: 12) }
  let(:calendar_connection) { instance_double(CalendarConnection, calendar_enabled?: true) }
  let(:active_connections) do
    instance_double(ActiveRecord::Associations::CollectionProxy, exists?: true, find_by: calendar_connection)
  end
  let(:appointments) do
    instance_double(Captain::AppointmentsSettings, enabled?: true, calendar_connection_id: 22, calendar_id: 'cal-1')
  end
  let(:captain_inbox) { instance_double(CaptainInbox, appointments_enabled: true) }
  let(:assistant) do
    instance_double(
      Captain::Assistant,
      account: instance_double(
        Account,
        calendar_connections: instance_double(ActiveRecord::Associations::CollectionProxy, active: active_connections)
      ),
      appointments: appointments,
      captain_inboxes: instance_double(ActiveRecord::Associations::CollectionProxy, find_by: captain_inbox)
    )
  end

  it 'returns not_connected without an active calendar connection' do
    allow(active_connections).to receive(:exists?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'not_connected', reason: 'not_connected_calendar', count: nil)
  end

  it 'returns off when assistant appointments are disabled' do
    allow(appointments).to receive(:enabled?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'disabled', count: nil)
  end

  it 'returns needs_setup when the selected calendar is not active or enabled' do
    allow(active_connections).to receive(:find_by).and_return(nil)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'no_calendar_selected', count: nil)

    allow(active_connections).to receive(:find_by).and_return(calendar_connection)
    allow(calendar_connection).to receive(:calendar_enabled?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'no_calendar_selected', count: nil)
  end

  it 'returns off when this inbox disables appointments and ready when enabled' do
    allow(assistant.captain_inboxes).to receive(:find_by).and_return(instance_double(CaptainInbox, appointments_enabled: false))
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'disabled', count: nil)

    allow(assistant.captain_inboxes).to receive(:find_by).and_return(captain_inbox)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'ready', reason: nil, count: nil)
  end
end
