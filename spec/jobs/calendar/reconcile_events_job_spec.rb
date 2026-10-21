require 'rails_helper'

RSpec.describe Calendar::ReconcileEventsJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) { create(:calendar_connection, account: account, access_token: 'access', access_token_expires_at: 1.day.from_now) }
  let(:event) { create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 2.days.from_now) }
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:remote) do
    { 'status' => 'confirmed', 'summary' => 'Moved by Google', 'start' => { 'dateTime' => 3.days.from_now.iso8601 },
      'end' => { 'dateTime' => (3.days.from_now + 30.minutes).iso8601 } }
  end

  before do
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_event).and_return(remote)
  end

  around { |example| travel_to(Time.zone.parse('2030-01-10T10:00:00Z')) { example.run } }

  it 'reconciles a linked human appointment and persists derived contact values through the existing callback' do
    Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: Calendar::AppointmentAttributes::Definitions::TYPES.keys)
    event

    perform_enqueued_jobs(only: Calendar::AppointmentAttributes::UpdateJob, at: Time.current) { described_class.perform_now }

    expect(event.reload).to have_attributes(start_at: 3.days.from_now, summary: 'Moved by Google', booking_source: 'manual')
    expect(contact.reload.custom_attributes).to include('proxima_cita' => 3.days.from_now.utc.iso8601,
                                                        'proxima_cita_titulo' => 'Moved by Google', 'total_citas' => 1)
    expect(event.activities.where(action: 'moved_in_google').count).to eq(1)
    expect { described_class.perform_now }.not_to change(CalendarEventActivity, :count)
  end

  it 'clears derived values after a confirmed remote cancellation' do
    Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: Calendar::AppointmentAttributes::Definitions::TYPES.keys)
    event
    allow(client).to receive(:get_event).and_return('status' => 'cancelled')

    perform_enqueued_jobs(only: Calendar::AppointmentAttributes::UpdateJob, at: Time.current) { described_class.perform_now }

    expect(contact.reload.custom_attributes).to include('proxima_cita' => nil, 'proxima_cita_titulo' => nil, 'total_citas' => 0)
    expect(event.reload.discarded?).to be(true)
  end

  it 'bounds each page, continues by id and visits later appointments without duplicating activities' do
    stub_const('Calendar::ReconcileEventsJob::BATCH_SIZE', 2)
    first = event
    second = create(:calendar_event, calendar_connection: connection, contact: contact)
    third = create(:calendar_event, calendar_connection: connection, contact: contact)

    expect { described_class.perform_now }.to have_enqueued_job(described_class).with(second.id)
    expect(client).to have_received(:get_event).twice
    expect(third.reload.summary).not_to eq('Moved by Google')
    described_class.perform_now(second.id)

    expect([first, second, third].map { |item| item.reload.summary }).to all(eq('Moved by Google'))
    expect(client).to have_received(:get_event).exactly(3).times
  end

  it 'includes recently elapsed slots but excludes old, cancelled and unlinked appointments' do
    recent = create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 2.hours.ago)
    create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 3.days.ago)
    create(:calendar_event, calendar_connection: connection, contact: contact, appointment_status: 'cancelled')
    create(:calendar_event, calendar_connection: connection)

    described_class.perform_now

    expect(client).to have_received(:get_event).once
    expect(recent.reload.start_at).to eq(3.days.from_now)
  end

  it 'reports a temporary failure, preserves the appointment and continues the page' do
    first = event
    second = create(:calendar_event, calendar_connection: connection, contact: contact)
    allow(client).to receive(:get_event).with(calendar_id: first.external_calendar_id, event_id: first.google_event_id)
                                        .and_raise(Net::ReadTimeout)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now

    expect(first.reload).to have_attributes(summary: 'Appointment', deleted_at: nil)
    expect(second.reload.summary).to eq('Moved by Google')
    expect(tracker).to have_received(:capture_exception).once
  end
end
