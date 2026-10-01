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
  end

  after { Redis::Alfred.delete(event_lock_key('stale-1')) }

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
end
