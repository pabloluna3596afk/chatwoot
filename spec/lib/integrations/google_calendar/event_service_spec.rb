require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:created_calls) { [] }
  let(:service) { described_class.new(account: account, user: user, connection: connection) }

  # Guayaquil is UTC-5 all year, which is the fallback timezone when the account has none.
  let(:slot_start) { '2030-01-15T10:00:00-05:00' }
  let(:slot_end) { '2030-01-15T10:30:00-05:00' }

  def google_event_for(id, kwargs)
    {
      'id' => id, 'etag' => '"etag-1"', 'summary' => kwargs[:summary], 'htmlLink' => 'https://calendar.test/event',
      'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 }
    }
  end

  def create_params(overrides = {})
    { calendar_id: 'cal-1', summary: 'Consulta', start: slot_start, end: slot_end, contact_id: contact.id }.merge(overrides)
  end

  def local_event(attrs = {})
    CalendarEvent.create!(
      {
        account: account, calendar_connection: connection, external_calendar_id: 'cal-1', google_event_id: "local-#{SecureRandom.hex(4)}",
        summary: 'Existing', start_at: Time.zone.parse(slot_start), end_at: Time.zone.parse(slot_end)
      }.merge(attrs)
    )
  end

  def booking_lock_key
    format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: account.id, calendar_id: 'cal-1')
  end

  def event_lock_key(event_id)
    format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: event_id)
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      created_calls << kwargs
      google_event_for("g-#{created_calls.size}", kwargs)
    end
    allow(client).to receive(:update_event) { |**kwargs| google_event_for(kwargs[:event_id], kwargs) }
    allow(client).to receive(:delete_event).and_return({})
    allow(client).to receive(:get_event) do |event_id:, **|
      record = connection.calendar_events.find_by!(google_event_id: event_id)
      google_event_for(event_id, summary: record.summary, start_at: record.start_at, end_at: record.end_at)
    end
  end

  after do
    Redis::Alfred.delete(booking_lock_key)
    %w[g-1 g-2 external].each { |event_id| Redis::Alfred.delete(event_lock_key(event_id)) }
  end

  describe 'association authorization without controller context' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    [:create, :update, :destroy].each do |operation|
      it "authorizes #{operation} before accessing Google", :aggregate_failures do
        record = local_event(conversation: conversation, contact: contact)
        original = record.reload.attributes
        params = create_params(conversation_id: conversation.display_id, note: 'Requested')

        expect do
          if operation == :create
            service.create(params)
          else
            service.public_send(operation, record.google_event_id, params)
          end
        end.to(raise_error { |error| expect(error.class.name).to eq('Pundit::NotAuthorizedError') })
        expect(Integrations::GoogleCalendar::Client).not_to have_received(:new)
        expect(record.reload.attributes).to eq(original)
        expect(record.activities).to be_empty
        expect(conversation.messages.count).to eq(0)
      end
    end

    it 'rejects mismatched people before looking for an available slot' do
      create(:inbox_member, user: user, inbox: conversation.inbox)
      other_contact = create(:contact, account: account)

      expect do
        service.create(create_params(conversation_id: conversation.display_id, contact_id: other_contact.id))
      end.to(raise_error { |error| expect(error.class.name).to eq('Integrations::GoogleCalendar::EventService::ContactMismatch') })
      expect(Integrations::GoogleCalendar::Client).not_to have_received(:new)
      expect(CalendarEvent.count).to eq(0)
      expect(CalendarEventActivity.count).to eq(0)
    end
  end

  describe 'appointment status validation and cancellation' do
    [nil, '', 123, true, [], {}, 'unknown', 'cancelled', 'rescheduled'].each do |status|
      it "rejects invalid creation status #{status.inspect} before Google" do
        expect { service.create(create_params(appointment_status: status)) }.to raise_error(described_class::InvalidAppointmentStatus)
        expect(client).not_to have_received(:create_event)
        expect(CalendarEvent.count).to eq(0)
      end
    end

    it 'records status-only changes in the activity history' do
      service.create(create_params(appointment_status: 'pending_confirmation'))
      service.update('g-1', create_params(appointment_status: 'confirmed'))

      record = connection.calendar_events.find_by!(google_event_id: 'g-1')
      expect(record.appointment_status).to eq('confirmed')
      expect(record.activities.find_by!(action: 'updated').details).to include('appointment_status' => %w[pending_confirmation confirmed])
    end

    it 'automatically marks an unconfirmed appointment as rescheduled when moved' do
      service.create(create_params(appointment_status: 'pending_confirmation'))
      result = service.update('g-1', create_params(start: '2030-01-15T11:00:00-05:00', end: '2030-01-15T11:30:00-05:00'))

      expect(result[:appointment_status]).to eq('rescheduled')
    end

    it 'preserves confirmation when moving a confirmed appointment' do
      service.create(create_params(appointment_status: 'confirmed'))
      result = service.update('g-1', create_params(start: '2030-01-15T11:00:00-05:00', end: '2030-01-15T11:30:00-05:00'))

      expect(result[:appointment_status]).to eq('confirmed')
    end

    it 'rejects rescheduled without a move before Google' do
      service.create(create_params)

      expect { service.update('g-1', create_params(appointment_status: 'rescheduled')) }.to raise_error(described_class::InvalidAppointmentStatus)
      expect(client).not_to have_received(:update_event)
    end

    it 'requires a reason for status-based cancellation without calling Google' do
      service.create(create_params)

      expect { service.update('g-1', { calendar_id: 'cal-1', appointment_status: 'cancelled' }) }.to raise_error(described_class::MissingDeleteNote)
      expect(client).not_to have_received(:delete_event)
      expect(client).not_to have_received(:update_event)
    end

    it 'cancels through destroy, releases the slot, and removes the next appointment' do
      service.create(create_params(appointment_status: 'confirmed'))
      result = service.update('g-1', { calendar_id: 'cal-1', appointment_status: 'cancelled', note: 'Customer request', etag: 'old' })

      record = connection.calendar_events.find_by!(google_event_id: 'g-1')
      expect(record).to have_attributes(appointment_status: 'cancelled', deleted_at: be_present, deleted_by: user, idempotency_key: nil)
      expect(result).to include(deleted: true, deleted_note: 'Customer request', appointment_status: 'cancelled')
      expect(client).to have_received(:delete_event).with(calendar_id: 'cal-1', event_id: 'g-1', etag: 'old')
      expect(client).not_to have_received(:update_event)
      expect(service.list_for_contact(contact_id: contact.id)).to be_empty
      expect { service.create(create_params) }.not_to raise_error
    end

    it 'does not revive a cancelled event' do
      service.create(create_params)
      service.destroy('g-1', calendar_id: 'cal-1', note: 'Customer request')

      expect { service.update('g-1', create_params(appointment_status: 'confirmed')) }.to raise_error(described_class::EventCancelled)
      expect(client).not_to have_received(:update_event)
    end

    it 'rejects update of a deleted event even when status is omitted' do
      service.create(create_params)
      service.destroy('g-1', calendar_id: 'cal-1', note: 'Customer request')

      expect { service.update('g-1', create_params) }.to raise_error(described_class::EventCancelled)
      expect(client).not_to have_received(:update_event)
    end

    it 'rejects edits to legacy status-only cancellations with the dedicated error' do
      record = local_event(appointment_status: 'cancelled')

      expect { service.update(record.google_event_id, create_params(summary: 'Edited')) }.to raise_error(described_class::EventCancelled)
      expect(client).not_to have_received(:update_event)
      expect(record.reload.summary).to eq('Existing')
    end

    it 'stores the title and reason when cancelling a Google-only event' do
      allow(client).to receive(:get_event).with(calendar_id: 'cal-1', event_id: 'external').and_return(
        'id' => 'external', 'summary' => 'External meeting', 'start' => { 'dateTime' => slot_start }, 'end' => { 'dateTime' => slot_end }
      )
      result = service.update('external', { calendar_id: 'cal-1', appointment_status: 'cancelled', note: 'Customer request' })

      expect(result).to include(summary: 'External meeting', deleted: true, appointment_status: 'cancelled', deleted_note: 'Customer request')
      expect(client).not_to have_received(:update_event)
    end
  end

  describe 'editing appointments outside current availability' do
    it 'allows note and status changes when opening hours have changed since booking' do
      service.create(create_params(appointment_status: 'pending_confirmation'))
      connection.connection_calendars.first.update!(hour_start: 12)

      result = service.update('g-1', create_params(description: 'Updated note', appointment_status: 'confirmed'))

      expect(result).to include(appointment_status: 'confirmed', start: slot_start)
      expect(connection.calendar_events.find_by!(google_event_id: 'g-1').invitation_text).to eq('Updated note')
      expect(client).to have_received(:update_event).once
    end

    it 'allows an unchanged slot on a day that is now closed' do
      service.create(create_params)
      connection.connection_calendars.first.update!(working_days: [1])

      expect { service.update('g-1', create_params(summary: 'Updated title')) }.not_to raise_error
      expect(client).to have_received(:update_event).once
    end

    it 'rejects changing only the end outside current hours before updating Google' do
      service.create(create_params)
      connection.connection_calendars.first.update!(hour_start: 12)

      expect { service.update('g-1', create_params(end: '2030-01-15T11:00:00-05:00')) }.to raise_error(described_class::OutsideHours)
      expect(client).not_to have_received(:update_event)
    end
  end

  describe '#create' do
    context 'when the booking lease is lost', :real_redis do
      it 'excludes a competing booking during a slow Google availability read' do
        competitor = described_class.new(account: account, user: user, connection: connection)
        allow(client).to receive(:list_events) do
          sleep 21
          expect { competitor.create(create_params) }.to raise_error(described_class::SlotBusy)
          []
        end

        expect(service.create(create_params)[:id]).to eq('g-1')
        expect(client).to have_received(:create_event).once
        expect(connection.calendar_events.count).to eq(1)
      end

      it 'does not POST after losing ownership during the availability read' do
        allow(client).to receive(:list_events) do
          Redis::Alfred.set(booking_lock_key, 'replacement', ex: 20)
          []
        end

        expect { service.create(create_params) }.to raise_error(described_class::SlotBusy)
        expect(client).not_to have_received(:create_event)
        expect(CalendarEvent.count).to eq(0)
        expect(Redis::Alfred.get(booking_lock_key)).to eq('replacement')
      end

      it 'records an in-flight POST result but performs no further remote write or notification' do
        allow(client).to receive(:create_event) do |**kwargs|
          Redis::Alfred.set(booking_lock_key, 'replacement', ex: 20)
          google_event_for('g-1', kwargs)
        end
        allow(service).to receive(:notify_conversation!)
        allow(service).to receive(:notify_contact_or_bot!)

        expect { service.create(create_params(idempotency_key: 'in-flight')) }.to raise_error(described_class::SlotBusy)
        expect(connection.calendar_events.find_by!(idempotency_key: 'in-flight').google_event_id).to eq('g-1')
        expect(client).not_to have_received(:update_event)
        expect(service).not_to have_received(:notify_conversation!)
        expect(service).not_to have_received(:notify_contact_or_bot!)
        expect(Redis::Alfred.get(booking_lock_key)).to eq('replacement')
      end
    end

    it 'books the slot, stores it locally and releases the booking lock' do
      result = service.create(create_params)

      expect(result[:id]).to eq('g-1')
      expect(result[:summary]).to eq('Consulta')
      record = CalendarEvent.find_by(google_event_id: 'g-1')
      expect(record).to have_attributes(account_id: account.id, contact_id: contact.id, external_calendar_id: 'cal-1')
      expect(record.activities.pluck(:action)).to eq(['created'])
      expect(Redis::Alfred.get(booking_lock_key)).to be_nil
    end

    it 'defaults the end to 30 minutes after the start' do
      service.create(create_params(end: nil))

      expect(created_calls.first[:end_at] - created_calls.first[:start_at]).to eq(30.minutes.to_i)
    end

    it 'rejects a range whose end is not after the start' do
      expect { service.create(create_params(end: slot_start)) }.to raise_error(described_class::InvalidRange)
      expect(client).not_to have_received(:create_event)
    end

    it 'rejects a calendar that is not enabled' do
      expect { service.create(create_params(calendar_id: 'other')) }.to raise_error(described_class::CalendarNotEnabled)
    end

    context 'with an idempotency key' do
      it 'releases A after moving to B and books a new event only in A' do
        params = create_params(idempotency_key: 'slot-a')
        first = service.create(params)
        service.update(first[:id], create_params(start: '2030-01-15T11:00:00-05:00', end: '2030-01-15T11:30:00-05:00'))

        second = service.create(params)
        retry_result = service.create(params)

        expect(second).to include(id: 'g-2', start: slot_start, end: slot_end)
        expect(retry_result[:id]).to eq(second[:id])
        expect(connection.calendar_events.find_by!(google_event_id: first[:id])).to have_attributes(
          start_at: Time.iso8601('2030-01-15T11:00:00-05:00'), end_at: Time.iso8601('2030-01-15T11:30:00-05:00'), idempotency_key: nil
        )
        expect(connection.calendar_events.find_by!(google_event_id: second[:id]).idempotency_key).to eq('slot-a')
        expect(client).to have_received(:create_event).twice
      end

      it 'preserves the key when editing without moving' do
        service.create(create_params(idempotency_key: 'slot-a'))
        service.update('g-1', create_params(summary: 'Edited'))

        expect(connection.calendar_events.find_by!(google_event_id: 'g-1').idempotency_key).to eq('slot-a')
      end

      it 'releases the key when only the end changes' do
        service.create(create_params(idempotency_key: 'slot-a'))
        service.update('g-1', create_params(end: '2030-01-15T10:45:00-05:00'))

        expect(connection.calendar_events.find_by!(google_event_id: 'g-1').idempotency_key).to be_nil
      end

      it 'releases the key when a Google move is synchronized' do
        service.create(create_params(idempotency_key: 'slot-a'))
        allow(client).to receive(:list_events).and_return(
          [google_event_for('g-1', summary: 'Moved', start_at: Time.iso8601('2030-01-15T11:00:00-05:00'),
                                   end_at: Time.iso8601('2030-01-15T11:30:00-05:00'))]
        )

        service.list(calendar_id: 'cal-1', time_min: slot_start, time_max: '2030-01-15T12:00:00-05:00')

        expect(connection.calendar_events.find_by!(google_event_id: 'g-1')).to have_attributes(
          start_at: Time.iso8601('2030-01-15T11:00:00-05:00'), idempotency_key: nil
        )
      end

      [:start, :end].each do |boundary|
        it "rejects a key collision with a different #{boundary} before returning an event" do
          service.create(create_params(idempotency_key: 'slot-a'))
          params = create_params({ :idempotency_key => 'slot-a', boundary => '2030-01-15T10:15:00-05:00' })

          expect { service.create(params) }.to raise_error(described_class::InvalidRange)
          expect(client).to have_received(:create_event).once
        end
      end

      it 'rejects a key owned by another connection to the same calendar before Google' do
        service.create(create_params(idempotency_key: 'slot-a'))
        other_connection = CalendarConnection.create!(
          account: account, provider: 'google', email: 'other@example.com', refresh_token: 'refresh'
        )
        other_connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Shared', is_enabled: true)
        other_service = described_class.new(account: account, user: user, connection: other_connection)

        expect { other_service.create(create_params(idempotency_key: 'slot-a')) }.to raise_error(described_class::InvalidRange)
        expect(other_connection.calendar_events).to be_empty
        expect(client).to have_received(:create_event).once
      end

      it 'rejects a key owned by another calendar on the same connection' do
        service.create(create_params(idempotency_key: 'slot-a'))
        connection.connection_calendars.create!(account: account, external_id: 'cal-2', summary: 'Other', is_enabled: true)

        expect { service.create(create_params(calendar_id: 'cal-2', idempotency_key: 'slot-a')) }.to raise_error(described_class::InvalidRange)
        expect(client).to have_received(:create_event).once
      end

      it 'returns the existing event and never double-books' do
        first = service.create(create_params(idempotency_key: 'key-1'))
        second = service.create(create_params(idempotency_key: 'key-1'))

        expect(second[:id]).to eq(first[:id])
        expect(created_calls.size).to eq(1)
        expect(CalendarEvent.where(idempotency_key: 'key-1').count).to eq(1)
      end

      it 'does not look up a cancelled event by its key' do
        service.create(create_params(idempotency_key: 'key-2'))
        service.destroy('g-1', calendar_id: 'cal-1', note: 'customer cancelled')

        expect(service.send(:find_by_idempotency_key, 'key-2')).to be_nil
      end

      it 'clears the key when the event is cancelled' do
        service.create(create_params(idempotency_key: 'key-3'))
        service.destroy('g-1', calendar_id: 'cal-1', note: 'customer cancelled')

        expect(CalendarEvent.find_by(google_event_id: 'g-1')).to have_attributes(idempotency_key: nil, deleted_at: be_present)
      end

      it 'books a fresh event with the key of a cancelled event' do
        service.create(create_params(idempotency_key: 'key-4'))
        service.destroy('g-1', calendar_id: 'cal-1', note: 'customer cancelled')

        result = service.create(create_params(idempotency_key: 'key-4'))

        expect(result[:id]).to eq('g-2')
        expect(created_calls.size).to eq(2)
        expect(CalendarEvent.where(idempotency_key: 'key-4').pluck(:google_event_id)).to eq(['g-2'])
      end

      it 'frees a key still held by an event cancelled before the key was cleared, before calling Google' do
        old = local_event(google_event_id: 'old-1', deleted_at: Time.current, idempotency_key: 'key-5')
        key_when_google_was_called = :never_called
        allow(client).to receive(:create_event) do |**kwargs|
          key_when_google_was_called = CalendarEvent.find(old.id).idempotency_key
          google_event_for('g-1', kwargs)
        end

        result = service.create(create_params(idempotency_key: 'key-5'))

        expect(key_when_google_was_called).to be_nil
        expect(result[:id]).to eq('g-1')
        expect(CalendarEvent.where(idempotency_key: 'key-5').pluck(:google_event_id)).to eq(['g-1'])
      end

      it 'does not touch the key of a live event with a different key' do
        service.create(create_params(idempotency_key: 'key-6'))

        service.create(create_params(idempotency_key: 'key-7', start: '2030-01-15T14:00:00-05:00', end: '2030-01-15T14:30:00-05:00'))

        expect(CalendarEvent.where(idempotency_key: %w[key-6 key-7]).count).to eq(2)
      end
    end

    context 'when the slot is taken' do
      it 'raises slot_busy with the conflict of a local event' do
        local_event(start_at: Time.zone.parse('2030-01-15T10:15:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:45:00-05:00'),
                    created_by: user)

        expect { service.create(create_params) }.to raise_error(described_class::SlotBusy) do |error|
          expect(error.conflict).to include(reason: 'overlap', summary: 'Existing')
          expect(error.conflict[:created_by]).to eq(name: user.name)
        end
        expect(client).not_to have_received(:create_event)
      end

      it 'raises slot_busy for an overlapping Google event' do
        allow(client).to receive(:list_events).and_return(
          [{ 'id' => 'ext-1', 'summary' => 'Busy', 'status' => 'confirmed',
             'start' => { 'dateTime' => '2030-01-15T10:15:00-05:00' }, 'end' => { 'dateTime' => '2030-01-15T10:45:00-05:00' } }]
        )

        expect { service.create(create_params) }.to raise_error(described_class::SlotBusy) do |error|
          expect(error.conflict).to include(reason: 'overlap', summary: 'Busy')
        end
      end

      it 'ignores cancelled and transparent Google events' do
        busy_window = { 'start' => { 'dateTime' => '2030-01-15T10:15:00-05:00' }, 'end' => { 'dateTime' => '2030-01-15T10:45:00-05:00' } }
        allow(client).to receive(:list_events).and_return(
          [busy_window.merge('id' => 'ext-1', 'status' => 'cancelled'), busy_window.merge('id' => 'ext-2', 'transparency' => 'transparent')]
        )

        expect { service.create(create_params) }.not_to raise_error
      end

      it 'allows a back-to-back booking' do
        local_event(start_at: Time.zone.parse('2030-01-15T10:30:00-05:00'), end_at: Time.zone.parse('2030-01-15T11:00:00-05:00'))

        expect { service.create(create_params) }.not_to raise_error
      end

      it 'raises slot_busy in_progress while the booking lock is held' do
        Redis::Alfred.set(booking_lock_key, 'someone-else', nx: true, ex: 20)

        expect { service.create(create_params) }.to raise_error(described_class::SlotBusy) do |error|
          expect(error.conflict).to eq(reason: 'in_progress')
        end
        expect(client).not_to have_received(:create_event)
        expect(Redis::Alfred.get(booking_lock_key)).to eq('someone-else')
      end
    end

    context 'with the booking source' do
      it "is 'manual' and sets created_by when a User books" do
        result = service.create(create_params)

        expect(result[:booking_source]).to eq('manual')
        expect(CalendarEvent.find_by(google_event_id: result[:id]).created_by).to eq(user)
      end

      it "is 'ai' with no created_by when an AgentBot books" do
        bot = create(:agent_bot, account: account)
        result = described_class.new(account: account, user: bot, connection: connection).create(create_params)

        expect(result[:booking_source]).to eq('ai')
        expect(CalendarEvent.find_by(google_event_id: result[:id]).created_by).to be_nil
      end
    end

    context 'with a bot follow-up policy' do
      let(:policy) { { enabled: true, confirmation: true, reminders_minutes_before: %w[1440 120] } }

      it 'marks the event pending_confirmation, normalizes the policy and enqueues the Panel AI job' do
        expect { service.create(create_params(bot_followup_policy: policy)) }
          .to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob).with(an_instance_of(Integer), 'created')

        record = CalendarEvent.find_by(google_event_id: 'g-1')
        expect(record.appointment_status).to eq('pending_confirmation')
        expect(record.bot_followup_policy).to include('enabled' => true, 'confirmation' => true, 'reminders_minutes_before' => [1440, 120])
      end

      it 'does not enqueue the Panel AI job when the policy is disabled' do
        expect { service.create(create_params(bot_followup_policy: policy.merge(enabled: false))) }
          .not_to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
      end

      it 'does not enqueue the Panel AI job without a policy' do
        expect { service.create(create_params) }.not_to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
        expect(CalendarEvent.find_by(google_event_id: 'g-1').appointment_status).to eq('none')
      end
    end
  end

  describe 'Captain mutations require the local owner' do
    [:update, :destroy].each do |operation|
      it "rejects #{operation} when only another connection owns the event" do
        other_connection = CalendarConnection.create!(
          account: account, provider: 'google', email: 'other@example.com', refresh_token: 'refresh'
        )
        record = local_event(calendar_connection: other_connection, google_event_id: 'external', contact: contact)
        params = create_params(note: 'Customer request')

        expect do
          if operation == :update
            service.update('external', params, require_local: true)
          else
            service.destroy('external', params.merge(require_local: true))
          end
        end.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
        expect(record.reload).to have_attributes(deleted_at: nil, summary: 'Existing')
        expect(client).not_to have_received(:update_event)
        expect(client).not_to have_received(:delete_event)
      end

      it "rejects #{operation} when the event belongs to another calendar" do
        record = local_event(external_calendar_id: 'cal-2', google_event_id: 'external')
        params = create_params(note: 'Customer request')

        expect do
          if operation == :update
            service.update('external', params, require_local: true)
          else
            service.destroy('external', params.merge(require_local: true))
          end
        end.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
        expect(record.reload.deleted_at).to be_nil
        expect(client).not_to have_received(:update_event)
        expect(client).not_to have_received(:delete_event)
      end
    end
  end

  describe '#update' do
    let(:moved) { { start: '2030-01-15T10:10:00-05:00', end: '2030-01-15T10:40:00-05:00' } }

    before do
      service.create(create_params)
      local_event(start_at: Time.zone.parse('2030-01-15T10:15:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:45:00-05:00'))
    end

    it 'does not re-check the slot when the time is unchanged' do
      result = service.update('g-1', create_params(summary: 'Renamed'))

      expect(result[:summary]).to eq('Renamed')
      expect(client).to have_received(:list_events).once
    end

    it 'checks the slot when the time changes' do
      expect { service.update('g-1', create_params(moved)) }.to raise_error(described_class::SlotBusy)
      expect(client).not_to have_received(:update_event)
    end

    it 'does not count the event itself as a conflict when it moves' do
      connection.calendar_events.where.not(google_event_id: 'g-1').destroy_all

      expect { service.update('g-1', create_params(moved)) }.not_to raise_error
      expect(client).to have_received(:update_event)
    end

    it 'moves the event to a free slot and logs the change' do
      free = { start: '2030-01-15T14:00:00-05:00', end: '2030-01-15T14:30:00-05:00' }
      service.update('g-1', create_params(free))

      record = CalendarEvent.find_by(google_event_id: 'g-1')
      expect(record.start_at).to eq(Time.zone.parse(free[:start]))
      expect(record.activities.pluck(:action)).to include('updated')
    end

    it 'forwards the etag to Google' do
      service.update('g-1', create_params(etag: '"old"'))

      expect(client).to have_received(:update_event).with(hash_including(event_id: 'g-1', etag: '"old"'))
    end

    it 'propagates a stale etag (Google 412)' do
      allow(client).to receive(:update_event)
        .and_raise(Integrations::GoogleCalendar::Client::PreconditionFailed.new('stale', code: 412))

      expect { service.update('g-1', create_params(etag: '"old"')) }
        .to raise_error(Integrations::GoogleCalendar::Client::PreconditionFailed)
    end

    it 'raises EventLocked when another user is editing the event' do
      other = create(:user, account: account)
      Integrations::GoogleCalendar::EventLock.new(account_id: account.id, event_id: 'g-1').acquire(other)

      expect { service.update('g-1', create_params) }.to raise_error(described_class::EventLocked) do |error|
        expect(error.holder_name).to eq(other.name)
      end
    end
  end

  describe '#destroy' do
    before { service.create(create_params) }

    it 'requires a note and does not touch Google without one' do
      expect { service.destroy('g-1', calendar_id: 'cal-1', note: ' ') }.to raise_error(described_class::MissingDeleteNote)
      expect(client).not_to have_received(:delete_event)
      expect(CalendarEvent.find_by(google_event_id: 'g-1').deleted_at).to be_nil
    end

    it 'soft-deletes the row and keeps a deleted activity with the note' do
      result = service.destroy('g-1', calendar_id: 'cal-1', note: 'customer cancelled', etag: '"etag-1"')

      record = CalendarEvent.find_by(google_event_id: 'g-1')
      expect(record.deleted_at).to be_present
      expect(record.deleted_by).to eq(user)
      expect(record.activities.find_by(action: 'deleted').details).to include('note' => 'customer cancelled')
      expect(result).to include(deleted: true, deleted_note: 'customer cancelled', appointment_status: 'cancelled')
      expect(client).to have_received(:delete_event).with(hash_including(calendar_id: 'cal-1', event_id: 'g-1', etag: '"etag-1"'))
    end

    it 'releases the event lock afterwards' do
      service.destroy('g-1', calendar_id: 'cal-1', note: 'customer cancelled')

      expect(Redis::Alfred.get(event_lock_key('g-1'))).to be_nil
    end
  end

  describe '#list_for_contact' do
    let(:other_contact) { create(:contact, account: account) }

    before do
      local_event(google_event_id: 'kept-1', contact: contact)
      local_event(google_event_id: 'deleted-1', contact: contact, deleted_at: Time.current)
      local_event(google_event_id: 'other-calendar', contact: contact, external_calendar_id: 'cal-2')
      local_event(google_event_id: 'other-contact', contact: other_contact)
      local_event(google_event_id: 'next-month', contact: contact,
                  start_at: Time.zone.parse('2030-02-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-02-15T10:30:00-05:00'))
    end

    it 'returns only kept events of the contact' do
      ids = service.list_for_contact(contact_id: contact.id).pluck(:id)

      expect(ids).to contain_exactly('kept-1', 'other-calendar', 'next-month')
    end

    it 'filters by calendar' do
      ids = service.list_for_contact(contact_id: contact.id, calendar_id: 'cal-1').pluck(:id)

      expect(ids).to contain_exactly('kept-1', 'next-month')
    end

    it 'filters by time range' do
      ids = service.list_for_contact(
        contact_id: contact.id, time_min: '2030-01-01T00:00:00-05:00', time_max: '2030-01-31T23:59:59-05:00'
      ).pluck(:id)

      expect(ids).to contain_exactly('kept-1', 'other-calendar')
    end

    it 'exposes the same lookup as list_by_contact' do
      expect(service.list_by_contact(contact_id: contact.id).pluck(:id)).to eq(service.list_for_contact(contact_id: contact.id).pluck(:id))
    end
  end

  describe '.creator_payload' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:conversation) { create(:conversation, account: account) }

    before { create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox) }

    it 'is the assistant with its photo for what Captain booked' do
      # a fresh load, as in a request: the factory's inbox cached that it had no assistant before the Captain inbox existed
      record = local_event(booking_source: 'ai', conversation: Conversation.find(conversation.id))

      expect(described_class.creator_payload(record)).to include(type: 'captain', name: assistant.name, thumbnail: assistant.avatar_or_default_url)
    end

    it 'is the person for what a person created, and nothing without a creator' do
      expect(described_class.creator_payload(local_event(created_by: user))).to include(type: 'user', id: user.id, name: user.name)
      expect(described_class.creator_payload(local_event)).to be_nil
    end

    it 'goes in the payload of the event' do
      payload = described_class.payload_from_record(local_event(created_by: user))

      expect(payload[:creator]).to include(type: 'user', name: user.name)
    end
  end

  describe 'the invite answer of the customer' do
    def at(start)
      { start_at: Time.zone.parse(start), end_at: Time.zone.parse(start) + 30.minutes }
    end

    def google_event(attendees)
      { 'id' => 'g-1', 'etag' => '"e"', 'summary' => 'Consulta', 'start' => { 'dateTime' => slot_start }, 'end' => { 'dateTime' => slot_end },
        'attendees' => attendees }
    end

    it 'reads the responseStatus of the invited customer, not of the organizer or the calendar' do
      attendees = [{ 'email' => 'agenda@example.com', 'organizer' => true, 'self' => true, 'responseStatus' => 'accepted' },
                   { 'email' => 'ana@example.com', 'responseStatus' => 'needsAction' }]

      expect(described_class.invitation_status_from(google_event(attendees))).to eq('needs_action')
      %w[accepted declined tentative].each do |answer|
        expect(described_class.invitation_status_from(google_event([{ 'email' => 'ana@example.com', 'responseStatus' => answer }]))).to eq(answer)
      end
    end

    it 'is nil without a customer attendee or with an answer it does not know' do
      expect(described_class.invitation_status_from(google_event([]))).to be_nil
      expect(described_class.invitation_status_from('id' => 'g-1')).to be_nil
      expect(described_class.invitation_status_from(google_event([{ 'email' => 'ana@example.com', 'responseStatus' => 'raro' }]))).to be_nil
    end

    it 'is kept when the event is created, and goes in the payload' do
      allow(client).to receive(:create_event) do |**kwargs|
        google_event_for('g-1', kwargs).merge('attendees' => [{ 'email' => 'ana@example.com', 'responseStatus' => 'needsAction' }])
      end

      payload = service.create(create_params(attendee_email: 'ana@example.com'))

      expect(payload[:invitation_status]).to eq('needs_action')
      expect(CalendarEvent.find_by(google_event_id: 'g-1').invitation_status).to eq('needs_action')
    end

    it 'is refreshed from Google, and a failure leaves what was known' do
      record = local_event(google_event_id: 'g-9', invitation_status: 'needs_action')
      allow(client).to receive(:get_event).and_return(google_event([{ 'email' => 'ana@example.com', 'responseStatus' => 'accepted' }]))

      expect(service.refresh_invitation_status!(record).invitation_status).to eq('accepted')

      allow(client).to receive(:get_event).and_raise(StandardError, 'down')
      expect(service.refresh_invitation_status!(record).invitation_status).to eq('accepted')
    end

    it 'refreshes only the upcoming appointments that are still unanswered, each one at most every few minutes' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      soon = local_event(google_event_id: 'g-1', **at('2030-02-01T10:00:00-05:00'))
      local_event(google_event_id: 'g-2', invitation_status: 'accepted', **at('2030-02-02T10:00:00-05:00'))
      local_event(google_event_id: 'g-3', **at('2020-01-01T10:00:00-05:00'))
      allow(client).to receive(:get_event).and_return(google_event([{ 'email' => 'ana@example.com', 'responseStatus' => 'declined' }]))

      2.times { described_class.refresh_upcoming_invitations(account, account.calendar_events, user: user) }

      expect(client).to have_received(:get_event).once
      expect(soon.reload.invitation_status).to eq('declined')
    end
  end
end
