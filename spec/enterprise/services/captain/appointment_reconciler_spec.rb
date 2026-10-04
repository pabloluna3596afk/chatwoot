require 'rails_helper'

RSpec.describe Captain::AppointmentReconciler do
  let(:account) { create(:account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
                               access_token: 'access', access_token_expires_at: 1.hour.from_now)
  end
  let(:appointments_config) { { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' } }
  let(:assistant) do
    create(:captain_assistant, account: account, config: { 'appointments' => appointments_config })
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:lines) { [] }
  let(:start_at) { Time.zone.parse('2030-01-15T10:00:00-05:00') }

  def booking(google_event_id, attrs = {})
    connection.calendar_events.create!(
      { account: account, external_calendar_id: 'cal-1', google_event_id: google_event_id, summary: google_event_id,
        start_at: start_at, end_at: start_at + 30.minutes, booking_source: 'ai', conversation: conversation,
        appointment_status: 'pending_confirmation' }.merge(attrs)
    )
  end

  def google_event(answer: 'needsAction', status: 'confirmed')
    { 'id' => 'x', 'status' => status, 'attendees' => [{ 'email' => 'ana@example.com', 'responseStatus' => answer }] }
  end

  def reconcile(apply:)
    described_class.new(account, apply: apply, log: ->(line) { lines << line }).perform
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_event).and_return(google_event(answer: 'accepted'))
  end

  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00-05:00')) { example.run } }

  context 'when running as a dry run' do
    it 'reports what it would do and writes nothing' do
      event = booking('g-1')

      result = reconcile(apply: false)

      expect(result.confirmed).to eq([event.id])
      expect(result.invitations).to eq([event.id])
      expect(result.reminders).to eq([event.id])
      expect(event.reload).to have_attributes(appointment_status: 'pending_confirmation', invitation_status: nil)
      expect(event.appointment_reminders).to be_empty
      expect(lines).to all(start_with('[dry run]'))
    end
  end

  context 'when applying' do
    it 'confirms the booking, reads the invite answer and schedules the missing reminders' do
      event = booking('g-1')

      reconcile(apply: true)

      expect(event.reload).to have_attributes(appointment_status: 'confirmed', invitation_status: 'accepted')
      expect(event.appointment_reminders.pluck(:kind)).to match_array(%w[reminder_1 reminder_2])
    end

    it 'does not schedule reminders twice, and leaves past, manual and cancelled appointments alone' do
      event = booking('g-1')
      Captain::AppointmentReminders::Scheduler.schedule(event, assistant: assistant, conversation: conversation)
      past = booking('g-2', start_at: 2.days.ago, end_at: 2.days.ago + 30.minutes)
      manual = booking('g-3', booking_source: 'manual')
      gone = booking('g-4', deleted_at: Time.current)

      result = reconcile(apply: true)

      expect(result.reminders).to be_empty
      expect(event.appointment_reminders.count).to eq(2)
      expect(past.reload.appointment_status).to eq('confirmed')
      expect(past.appointment_reminders).to be_empty
      expect([manual, gone].map { |item| item.reload.appointment_status }).to all(eq('pending_confirmation'))
    end

    it 'reports an appointment whose Google event is gone and keeps it' do
      event = booking('g-1')
      allow(client).to receive(:get_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('not found', code: 404))

      result = reconcile(apply: true)

      expect(result.missing_in_google).to eq([event.id])
      expect(event.reload.discarded?).to be(false)
    end

    it 'reports a failure and goes on with the next appointment' do
      first = booking('g-1')
      second = booking('g-2')
      calls = 0
      allow(client).to receive(:get_event) do
        calls += 1
        raise StandardError, 'boom' if calls == 1

        google_event(answer: 'declined')
      end

      result = reconcile(apply: true)

      expect(result.failed.size).to eq(1)
      expect([first, second].filter_map { |item| item.reload.invitation_status }).to eq(['declined'])
    end
  end
end
