require 'rails_helper'

RSpec.describe 'Variables API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) do
    create(:contact, account: account, document_number: 'DOC-123', additional_attributes: { 'country' => 'EC' }, name: 'MARÍA del CARMEN')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/variables" }
  let(:payload) do
    { surface: 'message', texts: ['{{ contact.document_number }}', '{{ contact.country_code }}', '{{ contact.name }}'],
      contexts: [{ contact_id: contact.id }] }
  end

  it 'requires authentication for metadata and preview' do
    get url
    expect(response).to have_http_status(:unauthorized)

    post "#{url}/preview", params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects users from another account' do
    outsider = create(:user)
    get url, headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)

    post "#{url}/preview", headers: outsider.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns only account definitions and metadata without personal values' do
    own = create(:custom_attribute_definition, account: account, attribute_key: 'nivel-vip')
    other = create(:custom_attribute_definition, attribute_key: 'foreign-secret')
    get url, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('schemaVersion' => 1, 'surface' => 'message')
    references = response.parsed_body['variables'].filter_map { |entry| entry['reference']['definitionId'] }
    expect(references).to include(own.id)
    expect(references).not_to include(other.id)
    expect(response.body).not_to include(contact.document_number, contact.name)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'returns one result per context and text, never cached or persisted' do
    second = create(:contact, account: account, document_number: 'DOC-456')
    payload[:contexts] << { contact_id: second.id }

    expect do
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:ok)
    results = response.parsed_body['results']
    expect(results.size).to eq(2)
    expect(results.first.map { |entry| entry['value'] }).to eq(['DOC-123', 'EC', 'María Del Carmen'])
    expect(results.last.first).to include('status' => 'value', 'value' => 'DOC-456')
    expect(response.parsed_body['timezone']).to be_present
    expect(response.headers['Cache-Control']).to include('no-store', 'private')
  end

  it 'does not look up contacts in another account' do
    payload[:contexts] = [{ contact_id: create(:contact).id }]
    post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('DOC-123')
  end

  it 'enforces conversation policy even for a contact in the same account' do
    agent = create(:user, account: account, role: :agent)
    conversation = create(:conversation, account: account, contact: contact)
    payload[:contexts] = [{ conversation_id: conversation.display_id }]
    post "#{url}/preview", headers: agent.create_new_auth_token, params: payload, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects inconsistent contact and conversation contexts' do
    conversation = create(:conversation, account: account)
    payload[:contexts] = [{ conversation_id: conversation.display_id, contact_id: contact.id }]
    post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects malformed types, unsupported fields and excessive batches at the boundary' do
    invalid = [
      { texts: 'not-an-array' }, { texts: [false] }, { texts: ['x' * 150_001] },
      { contexts: [{ contact_id: contact.id.to_s }] }, { contexts: [{ account_id: account.id }] },
      { contexts: [] }, { contexts: 'not-an-array' }, { contexts: [nil] }, { contexts: [{ contact_id: -1 }] },
      { texts: Array.new(101, 'x') }, { texts: Array.new(100, 'x'), contexts: Array.new(6, {}) },
      { surface: 'public_widget' }, { mode: false }
    ]
    invalid.each do |attributes|
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload.merge(attributes), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'reports absent contexts without exposing exception messages or other records' do
    payload[:texts] = ['{{ appointment.title }}', '{{ conversation.id }}', '{% if %}']
    payload[:contexts] = [{}]
    post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['results'].first.map { |entry| entry['status'] }).to eq(%w[unavailable unavailable invalid])
    expect(response.body).not_to include(contact.name)
  end

  it 'restricts campaign context to administrators and resolves the campaign sender' do
    campaign = create(:campaign, account: account, sender: admin)
    agent = create(:user, account: account, role: :agent)
    payload[:surface] = 'campaign'
    payload[:texts] = ['{{ agent.email }}']
    payload[:contexts] = [{ campaign_id: campaign.id, contact_id: contact.id }]
    post "#{url}/preview", headers: agent.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['results'].first.first['value']).to eq(admin.email)
  end

  context 'with an explicit FlowRun' do
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:flow) { Flow.create!(account: account, name: 'Preview') }
    let(:run) { FlowRun.create!(account: account, conversation: conversation, flow: flow, variables: { x: 'stored' }) }

    before do
      payload[:surface] = 'flow'
      payload[:texts] = ['{{ flow.x }}', '{{ flow.variables.x }}']
      payload[:contexts] = [{ conversation_id: conversation.display_id, flow_run_id: run.id }]
    end

    it 'previews the exact run using the same factory as delivery' do
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['results'].first.map { |entry| entry['value'] }).to eq(%w[stored stored])
    end

    it 'does not infer a run when none was explicitly supplied' do
      payload[:contexts].first.delete(:flow_run_id)
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

      expect(response.parsed_body['results'].first.map { |entry| entry['status'] }).to eq(%w[unavailable unavailable])
    end

    it 'rejects a run outside the supplied conversation' do
      other = create(:conversation, account: account)
      payload[:contexts].first[:conversation_id] = other.display_id
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'validates the run context before loading records' do
      payload[:contexts].first.delete(:conversation_id)
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      payload[:contexts].first[:conversation_id] = conversation.display_id
      payload[:surface] = 'message'
      post "#{url}/preview", headers: admin.create_new_auth_token, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'applies conversation visibility to the run preview' do
      agent = create(:user, account: account, role: :agent)
      post "#{url}/preview", headers: agent.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('stored')
    end
  end
end
