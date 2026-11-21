require 'rails_helper'

RSpec.describe 'WhatsApp template drafts API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_template_drafts" }
  let(:draft) { create(:whatsapp_template_draft, account: account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  it 'saves and reopens incomplete content without calling Meta or changing the cache' do
    post path, params: { draft: { title: 'Preparación', definition: { body: { text: '' } } } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body).to include('created_by_id' => admin.id, 'updated_by_id' => admin.id, 'submissions' => [])
    get "#{path}/#{id}", headers: headers
    expect(response.parsed_body['definition']).to eq('body' => { 'text' => '' })
    expect(response.parsed_body.to_json).not_to include('api_key', 'provider_config')
  end

  it 'allows a completely empty draft and a local copy without a destination' do
    post path, params: { draft: {} }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('definition' => {}, 'name' => nil, 'waba_id' => nil)
    id = response.parsed_body.fetch('id')
    post "#{path}/#{id}/duplicate", params: { destination: {} }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['source_draft_id']).to eq(id)
  end

  it 'lists only active drafts within the account' do
    draft
    create(:whatsapp_template_draft)
    create(:whatsapp_template_draft, account: account, archived_at: Time.current)
    get path, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([draft.id])
  end

  it 'edits with optimistic locking and rejects a stale editor' do
    patch "#{path}/#{draft.id}", params: { draft: { lock_version: 0, title: 'Nuevo título' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(draft.reload.updated_by).to eq(admin)
    patch "#{path}/#{draft.id}", params: { draft: { lock_version: 0, title: 'Edición antigua' } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(draft.reload.title).to eq('Nuevo título')
  end

  it 'rejects malformed payloads and another account destination with 422' do
    [{ definition: [] }, { definition: { body: { text: 42 } } }, { name: [] }, { preferred_channel_id: '2' }].each do |attributes|
      post path, params: { draft: attributes }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    post path, params: { draft: { preferred_channel_id: other.id, waba_id: other.provider_config['business_account_id'] } }, headers: headers,
               as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'duplicates into an independent destination without remote identifiers or active bindings changes' do
    destination = { preferred_channel_id: channel.id, waba_id: channel.provider_config['business_account_id'] }
    post "#{path}/#{draft.id}/duplicate", params: { destination: destination }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('source_draft_id' => draft.id, 'preferred_channel_id' => channel.id, 'submissions' => [])
    expect(response.parsed_body['name']).not_to eq(draft.name)
    expect(draft.reload.preferred_channel_id).to be_nil
  end

  it 'creates a new local version of an installed template with a different suggested name' do
    remote = { 'id' => 'meta-1', 'name' => 'installed', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
               'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['remote-handle'] } },
                                { 'type' => 'BODY', 'text' => 'Confirmación de cita.' }] }
    channel.update!(message_templates: [remote])
    post "#{path}/new_version", params: { channel_id: channel.id, remote_id: 'meta-1' }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['source_remote_id']).to eq('meta-1')
    expect(response.parsed_body['name']).to start_with('installed_v_')
    expect(response.parsed_body.to_json).not_to include('remote-handle')
    expect(channel.reload.message_templates).to eq([remote])
  end

  it 'archives locally and deletes a draft without history' do
    post "#{path}/#{draft.id}/archive", params: { lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(draft.reload.archived_at).to be_present
    delete "#{path}/#{draft.id}", params: { lock_version: draft.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(WhatsappTemplateDraft.exists?(draft.id)).to be(false)
  end

  it 'keeps submission history when deleting the local draft' do
    WhatsappTemplateSubmission.create!(whatsapp_template_draft: draft, account: account, revision: 0, waba_id: 'waba', name: draft.name,
                                       language: 'es', snapshot: { 'body' => 'original' }, payload_digest: 'digest')
    delete "#{path}/#{draft.id}", params: { lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(draft.reload.archived_at).to be_present
    expect(draft.submissions.count).to eq(1)
  end

  it 'uploads and downloads a local example using the account permission boundary' do
    file = fixture_file_upload('spec/assets/avatar.png', 'image/png')
    post "#{path}/#{draft.id}/media", params: { lock_version: '0', file: file }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('media', 'content_type')).to eq('image/png')
    get "#{path}/#{draft.id}/media", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(draft.reload.media.download)
    get "#{path}/#{draft.id}/media", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'validates locally before queueing and returns the same submission for double click' do
    post "#{path}/#{draft.id}/submit", params: { lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(draft.submissions).to be_empty
    draft.update!(preferred_channel: channel, waba_id: channel.provider_config['business_account_id'])
    post "#{path}/#{draft.id}/submit", params: { lock_version: draft.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    id = response.parsed_body['id']
    post "#{path}/#{draft.id}/submit", params: { lock_version: draft.lock_version }, headers: headers, as: :json
    expect(response.parsed_body['id']).to eq(id)
    expect(Whatsapp::SubmitTemplateDraftJob).to have_been_enqueued.with(id).exactly(2).times
    post "#{path}/#{draft.id}/submissions/#{id}/reconcile", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(Whatsapp::SubmitTemplateDraftJob).to have_been_enqueued.with(id, refresh: true)
  end

  it 'denies every management endpoint to an agent' do
    agent_headers = agent.create_new_auth_token
    [[:get, path, {}], [:get, "#{path}/#{draft.id}", {}], [:post, path, { draft: {} }],
     [:patch, "#{path}/#{draft.id}", { draft: { lock_version: 0 } }], [:delete, "#{path}/#{draft.id}", { lock_version: 0 }],
     [:post, "#{path}/#{draft.id}/archive", { lock_version: 0 }], [:post, "#{path}/#{draft.id}/duplicate", { destination: {} }],
     [:post, "#{path}/#{draft.id}/submit", { lock_version: 0 }], [:post, "#{path}/#{draft.id}/submissions/1/reconcile", {}],
     [:post, "#{path}/new_version", { channel_id: channel.id, remote_id: '1' }]].each do |verb, url, payload|
      public_send(verb, url, params: payload, headers: agent_headers.dup, as: :json)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'does not submit, duplicate, archive, or verify records of another account' do
    other = create(:whatsapp_template_draft)
    ["#{other.id}/submit", "#{other.id}/duplicate", "#{other.id}/archive", "#{other.id}/submissions/1/reconcile"].each do |suffix|
      post "#{path}/#{suffix}", params: { lock_version: 0 }, headers: headers.dup, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'does not expose another account drafts to an administrator' do
    other = create(:whatsapp_template_draft)
    [[:get, {}], [:patch, { draft: { lock_version: 0 } }], [:delete, { lock_version: 0 }]].each do |verb, payload|
      public_send(verb, "#{path}/#{other.id}", params: payload, headers: headers.dup, as: :json)
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'creates a blueprint draft with an optional destination and rejects unknown blueprints' do
    post "#{path}/from_blueprint", params: { blueprint_id: 'palu_cita_confirmacion' }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('preferred_channel_id' => nil, 'parameter_format' => 'POSITIONAL', 'language' => 'es')
    post "#{path}/from_blueprint", params: { blueprint_id: 'missing' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('unknown_blueprint')
  end

  it 'creates, reopens and duplicates a library draft without HTTP or an invented body' do
    post "#{path}/from_library", params: { library_template_name: 'appointment', name: 'appointment', language: 'es', category: 'UTILITY',
                                          button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '' }], channel_id: channel.id },
                                 headers: headers, as: :json
    expect(response).to have_http_status(:created)
    original = response.parsed_body
    get "#{path}/#{original.fetch('id')}", headers: headers
    expect(response.parsed_body['definition']).to eq(original['definition'])
    post "#{path}/#{original.fetch('id')}/duplicate", params: { destination: {} }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('definition' => original['definition'], 'submissions' => [])
    expect(response.parsed_body['name']).not_to eq(original['name'])
    expect(response.parsed_body['source_remote_id']).to be_nil
  end

  it 'accepts library drafts without a channel but refuses submission until a destination exists' do
    post "#{path}/from_library", params: { library_template_name: 'appointment', name: 'appointment', language: 'es', category: 'UTILITY' },
                                 headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    post "#{path}/#{id}/submit", params: { lock_version: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('destination_required')
  end

  it 'rejects malformed library definitions and identities at the request boundary' do
    valid = { library_template_name: 'appointment', name: 'appointment', language: 'es', category: 'UTILITY' }
    [{ library_template_name: '' }, { name: 'INVALID' }, { language: 'invalid_locale' }, { category: 'OTHER' },
     { button_inputs: {} }, { button_inputs: [42] }, { button_inputs: [{ type: 'URL', url: { base_url: 42 } }] },
     { preview: [] }, { preview: { body: 'a' * 1025 } }, { channel_id: '1' }].each do |invalid|
      post "#{path}/from_library", params: valid.merge(invalid), headers: headers.dup, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post path, params: { draft: { definition: { library: { template_name: 'appointment', language: 'es' }, body: { text: 'editable' } } } },
               headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  %w[from_library from_blueprint].each do |endpoint|
    it "restricts #{endpoint} to administrators and returns 404 for another account channel" do
      attributes = { library_template_name: 'appointment', name: 'appointment', language: 'es', category: 'UTILITY', blueprint_id: 'palu_reenganche' }
      post "#{path}/#{endpoint}", params: attributes, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      other = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      post "#{path}/#{endpoint}", params: attributes.merge(channel_id: other.id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
