require 'rails_helper'

RSpec.describe 'Onboarding assistant API', type: :request do
  let(:plan) { Plan.create!(name: 'Trial', slug: 'onboarding-api-trial', max_captain_assistants: 1) }
  let(:account) do
    create(:account, plan: plan, locale: 'es', custom_attributes: {
             'onboarding_version' => 2, 'onboarding_step' => 'assistant', 'business_type' => 'commerce'
           })
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/onboarding/assistant" }
  let(:attributes) { { name: 'Asistente', goal: 'Explica mis productos', tone: 'professional' } }

  before { allow(Llm::Config).to receive(:api_key_configured?).and_return(false) }

  it 'creates and resumes a draft with its input and AI availability, without activation' do
    2.times do
      post path, params: attributes, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
    assistant_id = account.reload.custom_attributes.fetch('onboarding_assistant_id')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['assistant']).to include('id' => assistant_id, 'paused_reason' => 'missing_key', 'inbox_ids' => [])
    expect(response.parsed_body.dig('assistant', 'config', 'onboarding')).to eq('goal' => attributes[:goal], 'tone' => attributes[:tone])
    expect(account.captain_assistants.count).to eq(1)
    expect(account.onboarding_step).to eq('assistant')
  end

  it 'returns an empty state without creating anything on read' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('assistant' => nil)
    expect(account.captain_assistants.count).to eq(0)

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['custom_attributes']).not_to have_key('onboarding_assistant_id')

    get '/api/v1/profile', headers: admin.create_new_auth_token, as: :json
    membership = response.parsed_body['accounts'].find { |item| item['id'] == account.id }
    expect(membership).not_to have_key('onboarding_assistant_id')
  end

  it 'keeps WhatsApp without an assistant until the explicit Captain inbox request' do
    channel = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
    inbox = channel.inbox
    headers = admin.create_new_auth_token

    post path, params: attributes, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    assistant_id = response.parsed_body.fetch('assistant').fetch('id')
    expect(inbox.reload.captain_assistant).to be_nil

    post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant_id}/inboxes",
         params: { inbox: { inbox_id: inbox.id } }, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(inbox.reload.captain_assistant.id).to eq(assistant_id)

    get path, headers: headers, as: :json
    expect(response.parsed_body['assistant']).to include('id' => assistant_id, 'inbox_ids' => [inbox.id])
    expect(account.captain_assistants.count).to eq(1)
  end

  it 'returns a translated plan limit with a stable code' do
    create(:captain_assistant, account: account)

    post path, params: attributes, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error_code' => 'assistant_limit', 'limit' => 1)
    expect(response.parsed_body['error']).to eq(I18n.t('captain.assistant.limit_exceeded', locale: :es, limit: 1))
    expect(account.reload.custom_attributes).not_to have_key('onboarding_assistant_id')
  end

  [{ name: '' }, { name: ['bad'] }, { goal: nil }, { goal: 'a' * 2001 }, { tone: 'other' }, { tone: ['friendly'] }].each do |invalid|
    it "rejects invalid input #{invalid.keys} at the boundary" do
      post path, params: attributes.merge(invalid), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.captain_assistants.count).to eq(0)
    end
  end

  it 'does not allow an agent to create the draft' do
    agent = create(:user, account: account, role: :agent)
    post path, params: attributes, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(account.captain_assistants.count).to eq(0)
  end

  it 'does not allow a legacy account to enter this step' do
    account.update!(custom_attributes: { 'onboarding_step' => 'inbox_setup' })

    post path, params: attributes, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.captain_assistants.count).to eq(0)
  end

  it 'exposes only the assistant pointer in account and membership payloads when present' do
    assistant = Onboarding::CaptainDraftService.new(account: account, **attributes).perform

    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('custom_attributes', 'onboarding_assistant_id')).to eq(assistant.id)

    get '/api/v1/profile', headers: admin.create_new_auth_token, as: :json
    membership = response.parsed_body['accounts'].find { |item| item['id'] == account.id }
    expect(membership['onboarding_assistant_id']).to eq(assistant.id)
    expect(membership).not_to have_key('onboarding_goal')
  end

  it 'serializes the step, version, business type, pointer and features through the real account and session views' do
    account.update!(custom_attributes: account.custom_attributes.merge('onboarding_step' => 'inbox_setup'))
    headers = admin.create_new_auth_token

    patch "/api/v1/accounts/#{account.id}/onboarding",
          params: { onboarding_step: 'inbox_setup', inbox_setup_result: 'skipped' }, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['custom_attributes']).to include('onboarding_step' => 'assistant', 'onboarding_version' => 2)

    post path, params: attributes, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    assistant_id = response.parsed_body.fetch('assistant').fetch('id')

    get "/api/v1/accounts/#{account.id}", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('name' => account.name)
    expect(response.parsed_body['custom_attributes']).to include(
      'business_type' => 'commerce', 'onboarding_step' => 'assistant', 'onboarding_version' => 2, 'onboarding_assistant_id' => assistant_id
    )
    expect(response.parsed_body['features']).to include('captain_integration' => true, 'captain_integration_v2' => true)

    get '/auth/validate_token', headers: headers, as: :json
    expect(response).to have_http_status(:success)
    membership = response.parsed_body.dig('payload', 'data', 'accounts').find { |item| item['id'] == account.id }
    expect(membership).to include('onboarding_step' => 'assistant', 'onboarding_version' => 2, 'onboarding_assistant_id' => assistant_id)

    patch "/api/v1/accounts/#{account.id}/onboarding", params: { onboarding_step: 'assistant' }, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['custom_attributes']).not_to have_key('onboarding_step')

    get '/auth/validate_token', headers: headers, as: :json
    expect(response).to have_http_status(:success)
    membership = response.parsed_body.dig('payload', 'data', 'accounts').find { |item| item['id'] == account.id }
    expect(membership['onboarding_step']).to be_nil
    expect(membership).to include('onboarding_version' => 2, 'onboarding_assistant_id' => assistant_id)

    get path, headers: headers, as: :json
    expect(response.parsed_body['assistant']).to include('id' => assistant_id, 'inbox_ids' => [])
    expect(account.captain_assistants.count).to eq(1)
  end
end
