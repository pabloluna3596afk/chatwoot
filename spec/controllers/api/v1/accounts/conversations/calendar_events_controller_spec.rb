require 'rails_helper'

RSpec.describe 'Conversation calendar events API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/calendar_events" }

  before { allow(Integrations::GoogleCalendar::EventService).to receive(:refresh_upcoming_invitations) }

  it 'denies an inaccessible conversation before refreshing invitations' do
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    expect(Integrations::GoogleCalendar::EventService).not_to have_received(:refresh_upcoming_invitations)
  end

  it 'allows an agent with access to the conversation' do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq([])
    expect(Integrations::GoogleCalendar::EventService).to have_received(:refresh_upcoming_invitations)
  end

  it 'does not resolve a conversation from another account' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/conversations/#{conversation.display_id}/calendar_events", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(Integrations::GoogleCalendar::EventService).not_to have_received(:refresh_upcoming_invitations)
  end
end
