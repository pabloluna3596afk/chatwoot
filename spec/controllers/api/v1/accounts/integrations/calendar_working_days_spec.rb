require 'rails_helper'

RSpec.describe 'Calendar Integration API working days', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: admin, display_name: 'Agenda'
    )
  end
  let!(:calendar) { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/#{connection.id}/calendars" }

  def calendar_payload(overrides = {})
    { external_id: 'cal-1', summary: 'Main', is_enabled: true, hour_start: 8, hour_end: 20 }.merge(overrides)
  end

  it 'returns the working days of each calendar' do
    calendar.update!(working_days: [1, 2, 3])

    patch url, params: { calendars: [calendar_payload] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].first).to include('id' => 'cal-1', 'working_days' => [1, 2, 3])
  end

  it 'saves the working days an administrator sends' do
    patch url, params: { calendars: [calendar_payload(working_days: [1, 2, 3, 4, 5])] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(calendar.reload.working_days).to eq([1, 2, 3, 4, 5])
  end

  it 'keeps the working days when a save does not send them (hours-only saves)' do
    calendar.update!(working_days: [2, 4])

    patch url, params: { calendars: [calendar_payload(hour_start: 9)] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(calendar.reload).to have_attributes(hour_start: 9, working_days: [2, 4])
  end

  it 'rejects an empty list and an invalid day' do
    [[], [8]].each do |days|
      patch url, params: { calendars: [calendar_payload(working_days: days)] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(calendar.reload.working_days).to eq([0, 1, 2, 3, 4, 5, 6])
  end

  it 'only lets administrators change them' do
    patch url, params: { calendars: [calendar_payload(working_days: [1])] }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(calendar.reload.working_days).to eq([0, 1, 2, 3, 4, 5, 6])
  end

  it 'lists the working days to agents through the calendars endpoint' do
    calendar.update!(working_days: [6])
    google = instance_double(Integrations::GoogleCalendar::Client, list_calendars: [{ 'id' => 'cal-1', 'summary' => 'Main' }])
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(google)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].first['working_days']).to eq([6])
  end
end
