require 'rails_helper'

RSpec.describe 'Calendar Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: admin, display_name: 'Agenda'
    )
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections" }
  let(:bot_headers) { { api_access_token: agent_bot.access_token.token } }
  let(:slot_start) { '2030-01-15T10:00:00-05:00' }
  let(:slot_end) { '2030-01-15T10:30:00-05:00' }

  def event_params(overrides = {})
    { connection_id: connection.id, calendar_id: 'cal-1', summary: 'Consulta', start: slot_start, end: slot_end,
      contact_id: contact.id }.merge(overrides)
  end

  def local_event(attrs = {})
    connection.calendar_events.create!(
      {
        account: account, external_calendar_id: 'cal-1', google_event_id: "local-#{SecureRandom.hex(4)}",
        summary: 'Existing', start_at: Time.zone.parse(slot_start), end_at: Time.zone.parse(slot_end)
      }.merge(attrs)
    )
  end

  def event_lock_key(event_id)
    format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: event_id)
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      { 'id' => "g-#{SecureRandom.hex(4)}", 'etag' => '"etag-1"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
    allow(client).to receive(:update_event) do |**kwargs|
      { 'id' => kwargs[:event_id], 'etag' => '"etag-2"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
    allow(client).to receive(:delete_event).and_return({})
    allow(client).to receive(:get_event) do |event_id:, **|
      record = connection.calendar_events.find_by!(google_event_id: event_id)
      { 'id' => event_id, 'etag' => record.etag, 'summary' => record.summary,
        'start' => { 'dateTime' => record.start_at.iso8601 }, 'end' => { 'dateTime' => record.end_at.iso8601 } }
    end
  end

  after { Redis::Alfred.delete(event_lock_key('stale-1')) }

  describe 'availability and status request validation' do
    let(:account) { create(:account, locale: 'es') }

    after do
      %w[invalid-status patch-cancel closed-day outside-hours].each { |id| Redis::Alfred.delete(event_lock_key(id)) }
    end

    outside_hours_ranges = [
      ['2030-01-15T07:30:00-05:00', '2030-01-15T08:00:00-05:00'],
      ['2030-01-15T19:45:00-05:00', '2030-01-15T20:15:00-05:00']
    ]
    cancelled_update_statuses = [nil, 'confirmed']
    boundary_ranges = [['08:00', '08:30'], ['19:30', '20:00']]

    [:agent, :bot].each do |actor|
      context "with #{actor} authentication" do
        let(:headers) { actor == :bot ? bot_headers : agent.create_new_auth_token }

        outside_hours_ranges.each do |start_at, end_at|
          it "rejects #{start_at} outside availability before Google" do
            post "#{base_url}/events", headers: headers, params: event_params(start: start_at, end: end_at), as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.outside_hours', locale: :es))
            expect(client).not_to have_received(:create_event)
            expect(CalendarEvent.count).to eq(0)
            record = local_event(google_event_id: 'outside-hours')
            patch "#{base_url}/events/#{record.google_event_id}",
                  headers: headers, params: event_params(start: start_at, end: end_at), as: :json
            expect(response).to have_http_status(:unprocessable_entity)
            expect(client).not_to have_received(:update_event)
          end
        end

        it 'rejects booking and moving onto a closed day' do
          connection.connection_calendars.first.update!(working_days: [1])
          record = local_event(google_event_id: 'closed-day', start_at: Time.zone.parse('2030-01-14T10:00:00-05:00'),
                               end_at: Time.zone.parse('2030-01-14T10:30:00-05:00'))

          post "#{base_url}/events", headers: headers, params: event_params, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          patch "#{base_url}/events/#{record.google_event_id}", headers: headers, params: event_params, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          expect(client).not_to have_received(:create_event)
          expect(client).not_to have_received(:update_event)
        end

        it 'allows note and status edits without moving a slot outside current availability' do
          connection.connection_calendars.first.update!(hour_start: 12, working_days: [1])
          record = local_event(google_event_id: 'outside-hours', appointment_status: 'pending_confirmation')
          update_params = event_params(description: 'Updated note', appointment_status: 'confirmed')

          patch "#{base_url}/events/#{record.google_event_id}", headers: headers, params: update_params, as: :json

          expect(response).to have_http_status(:ok)
          expect(record.reload).to have_attributes(
            appointment_status: 'confirmed', invitation_text: 'Updated note', start_at: Time.zone.parse(slot_start)
          )
          expect(client).to have_received(:update_event).once
        end

        cancelled_update_statuses.each do |status|
          it "returns a clear localized error when editing a cancelled appointment with status #{status.inspect}" do
            record = local_event(google_event_id: 'patch-cancel', appointment_status: 'cancelled')
            update_params = status ? event_params(appointment_status: status) : event_params

            patch "#{base_url}/events/#{record.google_event_id}", headers: headers, params: update_params, as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            expect(response.parsed_body['error']).to eq('La cita está cancelada y no se puede editar.')
            expect(client).not_to have_received(:update_event)
            expect(record.reload.appointment_status).to eq('cancelled')
          end
        end

        boundary_ranges.each do |start_time, end_time|
          it "accepts the exact boundary #{start_time}-#{end_time}" do
            post "#{base_url}/events",
                 headers: headers,
                 params: event_params(start: "2030-01-15T#{start_time}:00-05:00", end: "2030-01-15T#{end_time}:00-05:00"),
                 as: :json

            expect(response).to have_http_status(:ok)
          end
        end
      end
    end

    [nil, '', 1, true, [], {}, 'invalid', 'cancelled', 'rescheduled'].each do |status|
      it "rejects creation status #{status.inspect} before Google and persistence" do
        post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params(appointment_status: status), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.invalid_appointment_status', locale: :es))
        expect(client).not_to have_received(:create_event)
        expect(CalendarEvent.count).to eq(0)
      end
    end

    [nil, '', 1, true, [], {}, 'invalid', 'rescheduled'].each do |status|
      it "rejects update status #{status.inspect} without a remote or local change" do
        record = local_event(google_event_id: 'invalid-status')

        patch "#{base_url}/events/#{record.google_event_id}",
              headers: agent.create_new_auth_token, params: event_params(appointment_status: status), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.invalid_appointment_status', locale: :es))
        expect(client).not_to have_received(:update_event)
        expect(record.reload.appointment_status).to eq('none')
        expect(record.activities).to be_empty
      end
    end

    it 'requires a reason for PATCH cancellation' do
      record = local_event(google_event_id: 'patch-cancel')

      patch "#{base_url}/events/#{record.google_event_id}",
            headers: agent.create_new_auth_token, params: event_params(appointment_status: 'cancelled'), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.delete_note_required', locale: :es))
      expect(client).not_to have_received(:delete_event)
      expect(client).not_to have_received(:update_event)
    end

    it 'cancels through PATCH using the DELETE operation and its reason' do
      record = local_event(google_event_id: 'patch-cancel')

      patch "#{base_url}/events/#{record.google_event_id}",
            headers: agent.create_new_auth_token, params: event_params(appointment_status: 'cancelled', note: 'Customer request'), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('deleted' => true, 'appointment_status' => 'cancelled', 'deleted_note' => 'Customer request')
      expect(record.reload).to have_attributes(deleted_at: be_present, deleted_by: agent)
      expect(client).to have_received(:delete_event)
      expect(client).not_to have_received(:update_event)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/calendar_connections/events' do
    it 'books for an agent and marks the booking manual' do
      post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params(idempotency_key: 'k-1'), as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload).to include('summary' => 'Consulta', 'booking_source' => 'manual', 'calendar_id' => 'cal-1')
      expect(payload['contact']).to include('id' => contact.id)
    end

    it 'books for an AgentBot token and marks the booking ai' do
      post "#{base_url}/events", headers: bot_headers, params: event_params(idempotency_key: 'k-2'), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('booking_source' => 'ai')
      expect(CalendarEvent.last.created_by).to be_nil
    end

    it 'returns the same event for a repeated idempotency key' do
      2.times { post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params(idempotency_key: 'k-3'), as: :json }

      ids = CalendarEvent.where(idempotency_key: 'k-3').pluck(:google_event_id)
      expect(ids.size).to eq(1)
      expect(response.parsed_body['payload']['id']).to eq(ids.first)
      expect(client).to have_received(:create_event).once
    end

    it 'answers 422 with a slot_busy conflict when the time overlaps another event' do
      local_event(summary: 'Existing', created_by: admin,
                  start_at: Time.zone.parse('2030-01-15T10:15:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:45:00-05:00'))

      post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['code']).to eq('slot_busy')
      expect(body['conflict']).to include('reason' => 'overlap', 'summary' => 'Existing')
      expect(body['error']).to include('Existing', '10:15')
      expect(client).not_to have_received(:create_event)
    end

    it 'answers 422 when the calendar is not enabled' do
      post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params(calendar_id: 'other'), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.not_enabled'))
    end

    it 'answers 404 for a connection of another account' do
      other_connection = CalendarConnection.create!(
        account: create(:account), provider: 'google', email: 'other@example.com', refresh_token: 'refresh'
      )

      post "#{base_url}/events", headers: agent.create_new_auth_token, params: event_params(connection_id: other_connection.id), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/integrations/calendar_connections/events/:event_id' do
    it 'answers 412 when Google reports a stale etag' do
      allow(client).to receive(:update_event)
        .and_raise(Integrations::GoogleCalendar::Client::PreconditionFailed.new('stale', code: 412))

      patch "#{base_url}/events/stale-1", headers: agent.create_new_auth_token, params: event_params(etag: '"old"'), as: :json

      expect(response).to have_http_status(:precondition_failed)
      expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.stale'))
    end

    it 'answers 423 when another user is editing the event' do
      Integrations::GoogleCalendar::EventLock.new(account_id: account.id, event_id: 'stale-1').acquire(admin)

      patch "#{base_url}/events/stale-1", headers: agent.create_new_auth_token, params: event_params, as: :json

      expect(response).to have_http_status(:locked)
      expect(response.parsed_body['error']).to include(admin.name)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/integrations/calendar_connections/events/:event_id' do
    let(:event_id) { local_event(google_event_id: 'del-1', summary: 'To cancel').google_event_id }

    after { Redis::Alfred.delete(event_lock_key('del-1')) }

    it 'answers 422 when the note is missing' do
      delete "#{base_url}/events/#{event_id}", headers: agent.create_new_auth_token,
                                               params: { connection_id: connection.id, calendar_id: 'cal-1' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.delete_note_required'))
      expect(client).not_to have_received(:delete_event)
    end

    it 'soft-deletes the event when a note is given' do
      delete "#{base_url}/events/#{event_id}", headers: agent.create_new_auth_token,
                                               params: { connection_id: connection.id, calendar_id: 'cal-1', note: 'customer cancelled' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('deleted' => true, 'deleted_note' => 'customer cancelled')
      expect(CalendarEvent.find_by(google_event_id: 'del-1').deleted_at).to be_present
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/calendar_connections/events' do
    it 'lists the kept events of a contact from the local table' do
      local_event(google_event_id: 'mine-1', contact: contact)
      local_event(google_event_id: 'mine-deleted', contact: contact, deleted_at: Time.current)
      local_event(google_event_id: 'not-mine', contact: create(:contact, account: account))

      get "#{base_url}/events", headers: agent.create_new_auth_token,
                                params: { connection_id: connection.id, contact_id: contact.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to eq(['mine-1'])
      expect(client).not_to have_received(:list_events)
    end

    it 'lists the events of a calendar window from Google' do
      allow(client).to receive(:list_events).and_return(
        [{ 'id' => 'ext-1', 'summary' => 'External', 'start' => { 'dateTime' => slot_start }, 'end' => { 'dateTime' => slot_end } }]
      )

      get "#{base_url}/events", headers: bot_headers,
                                params: { connection_id: connection.id, calendar_id: 'cal-1',
                                          time_min: '2030-01-15T00:00:00-05:00', time_max: '2030-01-15T23:59:59-05:00' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to eq(['ext-1'])
    end
  end

  describe 'bot access limits' do
    it 'allows an AgentBot to list connections' do
      get base_url, headers: bot_headers

      expect(response).to have_http_status(:ok)
    end

    it 'does not allow an AgentBot to start the OAuth flow' do
      get "#{base_url}/oauth", headers: bot_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not allow an AgentBot to take an event lock' do
      post "#{base_url}/events/some-event/lock", headers: bot_headers, params: { connection_id: connection.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not allow an AgentBot to change the enabled calendars' do
      patch "#{base_url}/#{connection.id}/calendars", headers: bot_headers,
                                                      params: { calendars: [{ external_id: 'cal-1', is_enabled: false }] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
  it 'exposes the calendar zone on both profile bootstrap and account refresh' do
    account.update!(settings: { reporting_timezone: 'Eastern Time (US & Canada)' })
    get '/api/v1/profile', headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('accounts').find { |item| item['id'] == account.id }.fetch('calendar_timezone')).to eq('America/New_York')

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('calendar_timezone')).to eq('America/New_York')
  end

  it 'formats overlap errors in the account zone instead of a fixed offset' do
    account.update!(settings: { reporting_timezone: 'America/New_York' })
    local_event(start_at: Time.iso8601('2030-07-15T10:00:00-04:00'), end_at: Time.iso8601('2030-07-15T10:30:00-04:00'))

    post "#{base_url}/events", headers: agent.create_new_auth_token,
                               params: event_params(start: '2030-07-15T10:15:00-04:00', end: '2030-07-15T10:45:00-04:00'), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to include('10:00', '10:30')
  end
end
