require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Inboxes appointments switch', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:captain_inbox) { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }
  let(:connection) { CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'r') }
  let(:inboxes_url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def enable_appointments
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    assistant.update!(config: assistant.config.merge(
      'appointments' => { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }
    ))
  end

  it 'is on by default for a connected inbox' do
    expect(captain_inbox.reload.appointments_enabled).to be(true)

    get inboxes_url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:payload].first).to include(id: inbox.id, appointments_enabled: true)
    expect(json_response[:meta][:total_count]).to eq(1)
  end

  it 'is on for a newly connected inbox' do
    other = create(:inbox, account: account)

    post inboxes_url, params: { inbox: { inbox_id: other.id } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response).to include(id: other.id, appointments_enabled: true)
  end

  it 'lets an administrator switch it off and on again for one inbox' do
    patch "#{inboxes_url}/#{inbox.id}", params: { inbox: { appointments_enabled: false } },
                                       headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response).to include(id: inbox.id, appointments_enabled: false)
    expect(captain_inbox.reload.appointments_enabled).to be(false)

    patch "#{inboxes_url}/#{inbox.id}", params: { inbox: { appointments_enabled: true } },
                                       headers: admin.create_new_auth_token, as: :json

    expect(captain_inbox.reload.appointments_enabled).to be(true)
  end

  it 'does not touch the other inboxes of the assistant' do
    other = create(:inbox, account: account)
    other_captain_inbox = create(:captain_inbox, captain_assistant: assistant, inbox: other)

    patch "#{inboxes_url}/#{inbox.id}", params: { inbox: { appointments_enabled: false } },
                                       headers: admin.create_new_auth_token, as: :json

    expect(other_captain_inbox.reload.appointments_enabled).to be(true)
  end

  it 'does not let an agent change it' do
    patch "#{inboxes_url}/#{inbox.id}", params: { inbox: { appointments_enabled: false } },
                                       headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(captain_inbox.reload.appointments_enabled).to be(true)
  end

  it 'answers 404 for an inbox that is not connected to the assistant' do
    unconnected = create(:inbox, account: account)

    patch "#{inboxes_url}/#{unconnected.id}", params: { inbox: { appointments_enabled: false } },
                                             headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  describe 'effective setting' do
    it 'is off while the assistant has appointments off, whatever the inbox switch says' do
      expect(captain_inbox.appointments_active?).to be(false)
      expect(assistant.appointments_active_in?(inbox)).to be(false)
    end

    it 'is on when the assistant has appointments on and the inbox inherits the default' do
      enable_appointments

      expect(captain_inbox.reload.appointments_active?).to be(true)
      expect(assistant.reload.appointments_active_in?(inbox)).to be(true)
    end

    it 'is off in an inbox that switched it off, and on in the others' do
      enable_appointments
      other = create(:inbox, account: account)
      create(:captain_inbox, captain_assistant: assistant, inbox: other)
      captain_inbox.update!(appointments_enabled: false)

      expect(assistant.reload.appointments_active_in?(inbox)).to be(false)
      expect(assistant.appointments_active_in?(other)).to be(true)
    end

    it 'is off in an inbox the assistant is not connected to' do
      enable_appointments

      expect(assistant.reload.appointments_active_in?(create(:inbox, account: account))).to be(false)
    end
  end
end
