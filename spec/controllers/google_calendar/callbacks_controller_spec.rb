require 'rails_helper'

RSpec.describe 'Google Calendar OAuth callback', :real_redis, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:oauth) { Integrations::GoogleCalendar::Oauth }
  let(:tokens) { { 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'expires_in' => 3600 } }
  let(:state) do
    get "/api/v1/accounts/#{account.id}/integrations/calendar_connections/oauth", headers: admin.create_new_auth_token
    Rack::Utils.parse_query(URI.parse(response.parsed_body['url']).query).fetch('state')
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_CALENDAR_CLIENT_SECRET', nil).and_return('calendar-test-secret')
    allow(oauth).to receive(:configured?).and_return(true)
    allow(oauth).to receive(:exchange_code).with('valid-code').and_return(tokens)
    allow(oauth).to receive(:fetch_profile).with('new-access').and_return(email: 'agenda@example.com', name: 'Agenda')
  end

  it 'connects once through the API session cookie without callback authentication headers' do
    issued_state = state
    expect do
      get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    end.to change(CalendarConnection, :count).by(1)
    connection = account.calendar_connections.last
    expect(connection.connected_by).to eq(admin)
    expected_url = "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account.id}/settings/integrations/calendars?setup=#{connection.id}"
    expect(response).to redirect_to(expected_url)

    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).to have_received(:exchange_code).once
    expect(connection.reload.access_token).to eq('new-access')
    expect(account.calendar_connections.count).to eq(1)
  end

  it 'creates the contact attributes of appointments with the first connection' do
    allow(Calendar::AppointmentAttributes::BackfillJob).to receive(:perform_later)

    get '/google_calendar/callback', params: { state: state, code: 'valid-code' }

    expect(account.reload.appointment_attributes['keys']).to match_array(Calendar::AppointmentAttributes::Definitions::TYPES.keys)
  end

  it 'keeps the attributes the administrator already chose when another calendar connects' do
    account.update!(appointment_attributes: { 'keys' => %w[total_citas], 'enabled_keys' => %w[total_citas], 'results' => {} })

    get '/google_calendar/callback', params: { state: state, code: 'valid-code' }

    expect(account.reload.appointment_attributes['keys']).to eq(%w[total_citas])
  end

  it 'reconnects by email, retaining the refresh token when Google omits it' do
    connection = account.calendar_connections.create!(provider: :google, email: 'agenda@example.com', refresh_token: 'old-refresh')
    tokens.delete('refresh_token')
    issued_state = state
    expect do
      get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    end.not_to change(CalendarConnection, :count)
    expect(response).to have_http_status(:redirect)
    expect(connection.reload).to have_attributes(access_token: 'new-access', refresh_token: 'old-refresh', connected_by: admin)
  end

  it 'rejects replay without exchanging tokens or updating an existing connection' do
    issued_state = state
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    connection = account.calendar_connections.last
    saved_attributes = connection.attributes
    tokens['access_token'] = 'replayed-access'
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(oauth).to have_received(:exchange_code).once
    expect(response).to have_http_status(:unprocessable_entity)
    expect(connection.reload.attributes).to eq(saved_attributes)
    expect(account.calendar_connections.count).to eq(1)
  end

  it 'consumes the state even when the profile lookup fails' do
    issued_state = state
    allow(oauth).to receive(:fetch_profile).and_raise(StandardError, 'provider details')
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response.body).to eq(I18n.t('google_calendar.oauth.failed'))
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).to have_received(:exchange_code).once
    expect(account.calendar_connections).to be_empty
  end

  it 'consumes a callback with a missing code' do
    issued_state = state
    get '/google_calendar/callback', params: { state: issued_state }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
  end

  it 'consumes provider cancellation before a replay with a code' do
    issued_state = state
    get '/google_calendar/callback', params: { state: issued_state, error: 'access_denied', locale: 'es' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to eq(I18n.t('google_calendar.oauth.cancelled', locale: :es))
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
  end

  it 'consumes a state when token exchange fails' do
    allow(oauth).to receive(:exchange_code).and_raise(StandardError, 'provider details')
    issued_state = state
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response.body).to eq(I18n.t('google_calendar.oauth.failed'))
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).to have_received(:exchange_code).once
    expect(account.calendar_connections).to be_empty
  end

  it 'rejects an expired state before exchanging the code' do
    issued_state = state
    travel 11.minutes do
      get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
  end

  it 'rejects another browser session' do
    issued_state = state
    other_session = open_session
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    other_session.get "/api/v1/accounts/#{other_account.id}/integrations/calendar_connections/oauth", headers: other_admin.create_new_auth_token
    other_session.get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(other_session.response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
    expect(other_account.calendar_connections).to be_empty
  end

  it 'rejects a different authenticated user in the same browser' do
    issued_state = state
    other_user = create(:user, account: account, role: :administrator)
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }, headers: other_user.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
  end

  it 'rejects substitution of the account before exchanging the code' do
    payload = JWT.decode(state, nil, false).first.merge('sub' => create(:account).id)
    altered = JWT.encode(payload, 'calendar-test-secret', 'HS256')
    get '/google_calendar/callback', params: { state: altered, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(CalendarConnection.count).to eq(0)
  end

  [:demoted, :removed].each do |revocation|
    it "rejects the initiator whose account access was #{revocation}" do
      issued_state = state
      membership = account.account_users.find_by!(user: admin)
      revocation == :removed ? membership.destroy! : membership.update!(role: :agent)
      get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(oauth).not_to have_received(:exchange_code)
      expect(account.calendar_connections).to be_empty
    end
  end

  it 'rejects missing state with a localized message' do
    get '/google_calendar/callback', params: { code: 'valid-code', locale: 'es' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to eq(I18n.t('google_calendar.oauth.invalid_state', locale: :es))
    expect(oauth).not_to have_received(:exchange_code)
  end

  it 'rejects an account suspended after starting authorization' do
    issued_state = state
    account.update!(status: :suspended)
    get '/google_calendar/callback', params: { state: issued_state, code: 'valid-code' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(oauth).not_to have_received(:exchange_code)
    expect(account.calendar_connections).to be_empty
  end
end
