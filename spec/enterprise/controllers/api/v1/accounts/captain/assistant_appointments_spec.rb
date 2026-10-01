require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants appointments settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  before { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }

  it 'returns the defaults, disabled, for an assistant that never configured appointments' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:appointments]).to eq(
      enabled: false, calendar_connection_id: nil, calendar_id: nil, slot_duration_minutes: 30,
      required_contact_fields: %w[name phone email], min_notice_minutes: 60, booking_window_days: 14
    )
  end

  it 'saves the appointments settings' do
    settings = {
      enabled: true, calendar_connection_id: connection.id, calendar_id: 'cal-1', slot_duration_minutes: 45,
      required_contact_fields: %w[name phone], min_notice_minutes: 120, booking_window_days: 30
    }

    patch url, params: { assistant: { config: { appointments: settings } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:appointments]).to eq(settings)
    expect(assistant.reload.appointments).to be_enabled
  end

  it 'keeps the settings when another form saves the config it received' do
    assistant.update!(config: assistant.config.merge(
      'appointments' => { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }
    ))
    get url, headers: admin.create_new_auth_token, as: :json
    received = json_response[:config]

    patch url, params: { assistant: { config: received.merge(response_window: 'always') } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(assistant.reload.appointments).to be_enabled
    expect(assistant.appointments.calendar_id).to eq('cal-1')
  end

  it 'rejects enabling appointments without a valid calendar' do
    patch url, params: { assistant: { config: { appointments: { enabled: true } } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.appointments).not_to be_enabled
  end

  it 'rejects a calendar connection of another account' do
    other = CalendarConnection.create!(account: create(:account), provider: 'google', email: 'other@example.com', refresh_token: 'r')

    patch url, params: { assistant: { config: { appointments: { enabled: true, calendar_connection_id: other.id, calendar_id: 'cal-1' } } } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
