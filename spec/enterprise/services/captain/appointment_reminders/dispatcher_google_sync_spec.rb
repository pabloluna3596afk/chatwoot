require 'rails_helper'

RSpec.describe Captain::AppointmentReminders::Dispatcher do
  let(:account) { create(:account) }
  let(:connection) { create(:calendar_connection, account: account, access_token: 'access', access_token_expires_at: starts_at + 2.days) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:assistant) do
    create(:captain_assistant, account: account, config: {
             'appointments' => { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }
           })
  end
  let(:starts_at) { Time.zone.parse('2030-01-15T15:00:00Z') }
  let(:event) do
    create(:calendar_event, account: account, calendar_connection: connection, external_calendar_id: 'cal-1',
                            contact: contact, conversation: conversation, summary: 'Original', start_at: starts_at,
                            end_at: starts_at + 30.minutes, appointment_status: 'confirmed', idempotency_key: 'original-slot')
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:remote) do
    { 'id' => event.google_event_id, 'status' => 'confirmed', 'summary' => 'Google title',
      'start' => { 'dateTime' => starts_at.iso8601 }, 'end' => { 'dateTime' => (starts_at + 30.minutes).iso8601 },
      'attendees' => [{ 'responseStatus' => 'declined' }] }
  end
  let(:reminder) { event.appointment_reminders.find_by!(kind: 'reminder_1') }

  before do
    travel_to(starts_at - 2.days)
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox)
    Captain::AppointmentReminders::Scheduler.schedule(event, assistant: assistant, conversation: conversation)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_event).with(calendar_id: 'cal-1', event_id: event.google_event_id).and_return(remote)
    allow(ChatwootExceptionTracker).to(receive(:new).and_wrap_original { |_original, error, **_options| raise error })
    travel_to(starts_at - 24.hours + 1.minute)
  end

  it 'refreshes the title and invite answer from one read without treating declined as cancellation' do
    described_class.new.perform

    expect(client).to have_received(:get_event).once
    expect(event.reload).to have_attributes(summary: 'Google title', invitation_status: 'declined', appointment_status: 'confirmed')
    expect(conversation.messages.outgoing.last.content).to include('Google title')
  end

  it 'invalidates the old due time and sends only once at the new time, including retries' do
    remote['start']['dateTime'] = (starts_at + 1.day).iso8601
    remote['end']['dateTime'] = (starts_at + 1.day + 30.minutes).iso8601

    expect { 2.times { described_class.new.perform } }.not_to change(Message, :count)
    expect(event.reload).to have_attributes(start_at: starts_at + 1.day, idempotency_key: nil)
    expect(reminder.reload).to have_attributes(status: 'pending', scheduled_at: starts_at)
    expect(event.appointment_reminders.count).to eq(2)
    travel_to(starts_at + 1.minute)

    expect { 2.times { described_class.new.perform } }.to change(Message, :count).by(1)
    expect(reminder.reload.status).to eq('sent')
    expect(event.activities.where(action: 'moved_in_google').count).to eq(1)
  end

  it 'rechecks the due time after a local move even when the dispatcher already selected the old row' do
    selected = reminder
    event.update!(start_at: starts_at + 1.day, end_at: starts_at + 1.day + 30.minutes)

    expect { described_class.new.send(:dispatch, selected) }.not_to change(Message, :count)
    expect(client).not_to have_received(:get_event)
    expect(selected.reload.status).to eq('pending')
  end

  it 'rolls back a move and its reminder changes together when the surrounding transaction fails' do
    event.with_lock do
      event.update!(start_at: starts_at + 1.day, end_at: starts_at + 1.day + 30.minutes)
      expect(reminder.reload.scheduled_at).to eq(starts_at)
      raise ActiveRecord::Rollback
    end

    expect(event.reload.start_at).to eq(starts_at)
    expect(reminder.reload.scheduled_at).to eq(starts_at - 24.hours)
  end

  [404, 410, 'cancelled'].each do |outcome|
    it "cancels reminders and releases the local slot for Google #{outcome}" do
      if outcome == 'cancelled'
        allow(client).to receive(:get_event).and_return('status' => 'cancelled')
      else
        allow(client).to receive(:get_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('gone', code: outcome))
      end

      expect { 2.times { described_class.new.perform } }.not_to change(Message, :count)
      expect(event.reload).to have_attributes(appointment_status: 'cancelled', idempotency_key: nil)
      expect(event.deleted_at).to be_present
      expect(event.appointment_reminders.pluck(:status).uniq).to eq(['cancelled'])
      expect(account.calendar_events.kept).not_to include(event)
    end
  end

  [500, 503, :timeout].each do |outcome|
    it "waits without sending or cancelling after #{outcome}, then retries once" do
      error = outcome == :timeout ? Net::ReadTimeout.new : Integrations::GoogleCalendar::Client::Error.new('temporary', code: outcome)
      allow(client).to receive(:get_event).and_raise(error)

      expect { described_class.new.perform }.not_to change(Message, :count)
      expect(event.reload.discarded?).to be(false)
      expect(reminder.reload.status).to eq('pending')
      allow(client).to receive(:get_event).and_return(remote)

      expect { 2.times { described_class.new.perform } }.to change(Message, :count).by(1)
    end
  end
end
