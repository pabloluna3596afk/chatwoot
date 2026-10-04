require 'rails_helper'

RSpec.describe 'Calendar connections and the Panel AI follow-up', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections" }

  # The appointment modal offers the AI bot follow-up only when an AgentBot is active in some inbox.
  it 'says no AI bot is active when no inbox has one' do
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['panel_ai_active']).to be(false)
  end

  it 'says an AI bot is active when an inbox has one active' do
    inbox = create(:inbox, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: account), status: :active)

    get url, headers: agent.create_new_auth_token

    expect(response.parsed_body['panel_ai_active']).to be(true)
  end

  it 'ignores an AI bot that is switched off' do
    inbox = create(:inbox, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: account), status: :inactive)

    get url, headers: agent.create_new_auth_token

    expect(response.parsed_body['panel_ai_active']).to be(false)
  end
end
