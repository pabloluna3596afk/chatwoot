require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::AgentSessions', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant)
  end

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/agent_sessions/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the message has an agent session' do
      let(:document) { create(:captain_document, account: account, assistant: assistant, name: 'Password reset guide') }
      let(:documented_faq) do
        create(:captain_assistant_response, account: account, assistant: assistant,
                                            question: 'How do I reset my password?', documentable: document)
      end
      let(:used_faq) do
        create(:captain_assistant_response, account: account, assistant: assistant,
                                            question: 'How long do refunds take?', documentable: agent, status: :approved)
      end
      let(:scenario) { create(:captain_scenario, account: account, assistant: assistant, title: 'Refund flow') }
      let(:run_context) do
        [
          { 'role' => 'user', 'content' => 'I want a refund' },
          { 'role' => 'assistant', 'content' => '', 'agent_name' => 'Assistant',
            'tool_calls' => [{ 'id' => 'call_1', 'name' => 'faq_lookup', 'arguments' => { 'query' => 'refund' } }] },
          { 'role' => 'tool', 'content' => 'Refunds take 5 days', 'tool_call_id' => 'call_1' },
          { 'role' => 'assistant', 'content' => 'Refunds take 5 days', 'agent_name' => "scenario_#{scenario.id}_refund_flow" }
        ]
      end
      let!(:agent_session) do
        create(:captain_agent_session, account: account, assistant: assistant,
                                       subject: conversation, result: message,
                                       llm_model: 'openai-gpt-5.2', credits_consumed: 1.0,
                                       faq_ids: [documented_faq.id],
                                       used_faq_ids: [used_faq.id],
                                       document_ids: [document.id],
                                       cited_document_ids: [document.id],
                                       scenario_ids: [scenario.id],
                                       run_context: run_context)
      end

      it 'returns the session with hydrated citations and scenarios' do
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        aggregate_failures do
          expect(json_response[:id]).to eq(agent_session.id)
          expect(json_response[:message_id]).to eq(message.id)
          expect(json_response).not_to have_key(:llm_model)
          expect(json_response).not_to have_key(:credits_consumed)
          expect(json_response).not_to have_key(:run_context)
          expect(json_response[:technical]).to eq({})
          expect(json_response[:summary]).to eq(actions: [{ type: 'tool', name: 'faq_lookup' }])
          expect(response.body).not_to include('I want a refund', 'Refunds take 5 days', 'arguments', 'openai-gpt-5.2')

          citations = json_response[:citations].index_by { |citation| citation[:id] }
          expect(citations.keys).to contain_exactly(document.id)
          expect(citations[document.id][:title]).to eq('Password reset guide')
          expect(citations[document.id][:link]).to eq(document.external_link)

          expect(json_response[:used_faqs]).to eq([{ id: used_faq.id, title: 'How long do refunds take?' }])

          expect(json_response[:scenarios]).to eq([{ id: scenario.id, title: 'Refund flow' }])
        end
      end

      it 'returns only credits to administrators and all recorded technical fields to member SuperAdmins' do
        admin = create(:user, account: account, role: :administrator)
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", headers: admin.create_new_auth_token, as: :json
        expect(json_response[:technical]).to eq(credits_consumed: { status: 'recorded', value: 1.0 })
        super_admin = create(:super_admin)
        create(:account_user, account: account, user: super_admin, role: :administrator)
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", headers: super_admin.create_new_auth_token, as: :json
        expect(json_response[:technical]).to eq(model: { status: 'recorded', value: 'openai-gpt-5.2' },
                                                credits_consumed: { status: 'recorded', value: 1.0 }, cost: { status: 'not_recorded' })
        expect(json_response).not_to have_key(:run_context)
        expect(response.body).not_to include('I want a refund', 'arguments')
      end

      it 'denies private anchors and bots rather than inheriting conversation access' do
        message.update!(private: true)
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
        bot = create(:agent_bot, account: account)
        create(:agent_bot_inbox, agent_bot: bot, inbox: inbox)
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", headers: { api_access_token: bot.access_token.token }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not return a retained session whose subject belongs to another conversation' do
        agent_session.update!(subject: create(:conversation, account: account, inbox: inbox))
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'does not allow an agent without access to the conversation' do
        other_agent = create(:user, account: account, role: :agent)

        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}",
            headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the message has no agent session' do
      it 'returns not found' do
        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{message.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the message does not belong to the account' do
      it 'returns not found' do
        other_message = create(:message)

        get "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{other_message.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
