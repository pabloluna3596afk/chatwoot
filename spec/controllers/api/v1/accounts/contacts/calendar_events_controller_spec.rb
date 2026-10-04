require 'rails_helper'

RSpec.describe 'Contact calendar events API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
                               access_token: 'access', access_token_expires_at: 1.hour.from_now)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/calendar_events" }

  def event(google_event_id, start_at, attrs = {})
    connection.calendar_events.create!(
      { account: account, external_calendar_id: 'cal-1', google_event_id: google_event_id, summary: google_event_id,
        start_at: start_at, end_at: start_at + 30.minutes, contact: contact }.merge(attrs)
    )
  end

  before { allow(Integrations::GoogleCalendar::EventService).to receive(:refresh_upcoming_invitations) }

  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00-05:00')) { example.run } }

  it 'requires authentication' do
    get url

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the upcoming appointments of the contact in order, with who created them' do
    event('later', Time.zone.parse('2030-01-20T10:00:00-05:00'), created_by: agent)
    event('soon', Time.zone.parse('2030-01-15T10:00:00-05:00'), booking_source: 'ai')
    event('past', Time.zone.parse('2030-01-10T10:00:00-05:00'))
    event('gone', Time.zone.parse('2030-01-16T10:00:00-05:00'), deleted_at: Time.current)
    event('other', Time.zone.parse('2030-01-17T10:00:00-05:00'), contact: create(:contact, account: account))

    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    payload = response.parsed_response['payload']
    expect(payload.pluck('id')).to eq(%w[soon later])
    expect(payload.first['creator']).to include('type' => 'captain')
    expect(payload.last['creator']).to include('type' => 'user', 'name' => agent.name)
  end

  it 'refreshes the invite answers of the contact before answering' do
    event('soon', Time.zone.parse('2030-01-15T10:00:00-05:00'))

    get url, headers: agent.create_new_auth_token

    expect(Integrations::GoogleCalendar::EventService).to have_received(:refresh_upcoming_invitations)
      .with(account, anything, user: agent)
  end

  it 'does not read the contacts of another account' do
    other = create(:contact, account: create(:account))

    get "/api/v1/accounts/#{account.id}/contacts/#{other.id}/calendar_events", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:not_found)
  end
end
