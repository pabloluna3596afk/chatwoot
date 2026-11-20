require 'rails_helper'

RSpec.describe 'Captain decisions', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:super_admin) { create(:super_admin).tap { |user| create(:account_user, account: account, user: user, role: :administrator) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, sender: assistant, message_type: :outgoing) }
  let!(:decision) do
    create(:captain_decision, account: account, conversation: conversation, assistant: assistant, anchor_message: message,
                              technical_details: { model: 'test-model', credits_consumed: 0, cost: 0.001 }, reason_text: 'Operational reason')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/captain_decisions" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'returns safe details to agents and never trusts technical client parameters' do
    get "#{path}?message_id=#{message.id}&role=SuperAdmin&dev=true", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    payload = response.parsed_body.first
    expect(payload).to include('id' => decision.id, 'reason_text' => 'Operational reason', 'technical' => {}, 'can_change_setting' => false)
    expect(payload).not_to have_key('technical_details')
    expect(payload).not_to have_key('setting_destination')
    expect(response.body).not_to include('test-model', '0.001')
  end

  %w[close_unanswered nudge reengage reopen human_control disengage].each do |kind|
    it "returns #{kind} through the same role allowlists" do
      decision.update!(kind: kind, origin: 'time', reason_code: kind, reason_text: "Recorded #{kind}", technical_details: {})
      [agent, admin, super_admin].each do |user|
        get "#{path}?message_id=#{message.id}&role=SuperAdmin&dev=true", headers: user.create_new_auth_token
        expect(response).to have_http_status(:success)
        payload = response.parsed_body.first
        expect(payload).to include('kind' => kind, 'reason_text' => "Recorded #{kind}")
        if user == agent
          expect(payload['technical']).to eq({})
        elsif user == admin
          expect(payload['technical']).to eq('credits_consumed' => { 'status' => 'not_applicable' })
        else
          expect(payload['technical'].keys).to match_array(%w[model credits_consumed cost])
        end
        expect(payload).not_to have_key('technical_details')
      end
    end
  end

  it 'returns only recorded credits, including zero, to administrators' do
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['technical']).to eq('credits_consumed' => { 'status' => 'recorded', 'value' => 0 })
    expect(response.parsed_body['can_change_setting']).to be(true)
    expect(response.parsed_body['setting_destination']).to include("/accounts/#{account.id}/captain/#{assistant.id}/")
  end

  it 'returns model, credits and cost to a member SuperAdmin' do
    get "#{path}/#{decision.id}", headers: super_admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['technical']).to eq(
      'model' => { 'status' => 'recorded', 'value' => 'test-model' },
      'credits_consumed' => { 'status' => 'recorded', 'value' => 0 }, 'cost' => { 'status' => 'recorded', 'value' => 0.001 }
    )
  end

  it 'distinguishes unknown from not applicable without converting absence to zero' do
    decision.update!(technical_details: {})
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['technical']).to eq('credits_consumed' => { 'status' => 'not_recorded' })
    decision.update!(origin: 'rule')
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['technical']).to eq('credits_consumed' => { 'status' => 'not_applicable' })
  end

  it 'does not overwrite absent deduction evidence with a session delivery counter' do
    decision.update!(technical_details: {}, agent_session: create(:captain_agent_session, assistant: assistant, subject: conversation,
                                                                                          result: message, credits_consumed: 1))
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['technical']).to eq('credits_consumed' => { 'status' => 'not_recorded' })
  end

  it 'requires assistant update permission even for an administrator' do
    assistant.update!(config: assistant.config.merge('internal' => true))
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['can_change_setting']).to be(false)
    expect(response.parsed_body).not_to have_key('setting_destination')
  end

  it 'does not reveal private anchors to inbox-only agents, but allows the assigned agent and admin' do
    message.update!(private: true)
    get "#{path}?message_id=#{message.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "#{path}/#{decision.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    conversation.update!(assignee: agent)
    get "#{path}/#{decision.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
  end

  it 'enforces the conversation policy' do
    other_agent = create(:user, account: account, role: :agent)
    get "#{path}/#{decision.id}", headers: other_agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses bots even when the conversation policy would permit them' do
    bot = create(:agent_bot, account: account)
    create(:agent_bot_inbox, agent_bot: bot, inbox: inbox)
    get "#{path}/#{decision.id}", headers: { api_access_token: bot.access_token.token }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'isolates account, conversation, anchor and decision IDs' do
    foreign_message = create(:message)
    other_conversation = create(:conversation, account: account, inbox: inbox)
    get "#{path}?message_id=#{foreign_message.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{path}/#{create(:captain_decision).id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{account.id}/conversations/#{other_conversation.display_id}/captain_decisions/#{decision.id}",
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    outsider = create(:super_admin)
    get "#{path}/#{decision.id}", headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns at most two retained facts, ends at a new incoming turn, and never includes content' do
    travel 1.minute do
      create(:message, conversation: conversation, account: account, message_type: :activity,
                       content: 'SECRET', content_attributes: { activity: { type: 'conversation_status_changed', status: 'resolved' } })
      create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'CUSTOMER SECRET')
      create(:message, conversation: conversation, account: account, private: true, content: 'AI SECRET',
                       content_attributes: { captain_handoff: { source: 'tool' } })
    end
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    facts = response.parsed_body.dig('afterwards', 'facts')
    expect(facts.pluck('type')).to eq(%w[resolved new_incoming])
    expect(facts.all? { |fact| fact.keys.sort == %w[occurred_at type] }).to be(true)
    expect(response.body).not_to include('SECRET')
  end

  it 'hydrates only retained sources of this assistant and strips links containing secrets' do
    document = create(:captain_document, account: account, assistant: assistant, name: 'Authorized guide')
    document.update_column(:external_link, 'https://example.com/guide?token=secret') # rubocop:disable Rails/SkipsModelValidations -- simulate retained legacy URL
    faq = create(:captain_assistant_response, account: account, assistant: assistant, documentable: admin, status: :approved)
    decision.update!(evidence: { document_ids: [document.id], cited_document_ids: [document.id], used_faq_ids: [faq.id] })
    get "#{path}/#{decision.id}", headers: agent.create_new_auth_token
    sources = response.parsed_body.dig('evidence', 'sources')
    expect(sources['documents']).to eq([{ 'id' => document.id, 'title' => 'Authorized guide', 'link' => nil, 'usage' => 'cited' }])
    expect(sources['faqs']).to eq([{ 'id' => faq.id, 'title' => faq.question, 'usage' => 'used' }])
    expect(response.body).not_to include('token=secret')
  end

  it 'returns retained handoff and reopening facts in chronological order' do
    travel 1.minute do
      create(:message, account: account, conversation: conversation, private: true, message_type: :outgoing, sender: assistant,
                       content_attributes: { captain_handoff: { source: 'tool' } })
    end
    travel 2.minutes do
      create(:message, account: account, conversation: conversation, message_type: :activity,
                       content_attributes: { activity: { type: 'conversation_status_changed', status: 'open', previous_status: 'resolved' } })
    end
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body.dig('afterwards', 'facts').pluck('type')).to eq(%w[handoff reopened])
  end

  it 'reports missing retained facts and rejects invalid or absent message filters' do
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response.parsed_body['afterwards']).to eq('status' => 'not_recorded', 'facts' => [])
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{path}?message_id=not-an-id", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{path}/#{decision.id}invalid", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not rebuild deleted anchors or return decisions on message payloads' do
    expect(message.push_event_data.to_json).not_to include('captain_decisions', 'Operational reason', 'test-model')
    expect(message.webhook_data.to_json).not_to include('captain_decisions', 'Operational reason', 'test-model')
    message.delete
    get "#{path}/#{decision.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
