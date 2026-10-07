require 'rails_helper'

RSpec.describe 'WhatsApp flows (forms) API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/whatsapp_flows" }
  let(:definition) do
    { schema_version: 1,
      screens: [{ title: 'Tus datos', button: 'Enviar',
                  blocks: [{ type: 'heading', text: 'Hola' }, { type: 'short_text', key: 'nombre', label: 'Nombre', required: true }] }] }
  end
  let(:invalid_definition) do
    { schema_version: 1, screens: [{ title: '', button: 'Enviar', blocks: [{ type: 'short_text', key: 'Nombre', label: 'Nombre' }] }] }
  end

  describe 'who can do what' do
    it 'requires authentication' do
      get base_url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets an agent read the forms but not create, change, delete or check them' do
      flow = create(:whatsapp_flow, account: account)
      headers = agent.create_new_auth_token

      get base_url, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      get "#{base_url}/#{flow.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post base_url, params: { whatsapp_flow: { name: 'x', definition: definition } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{base_url}/#{flow.id}", params: { whatsapp_flow: { name: 'y' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{base_url}/#{flow.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{base_url}/validate", params: { definition: definition }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not show the forms of another account' do
      other = create(:whatsapp_flow)

      get "#{base_url}/#{other.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'unpublished changes' do
    let(:flow) { create(:whatsapp_flow, account: account) }
    let(:publication) do
      flow.whatsapp_flow_publications.create!(account: account, waba_id: '123456789', status: 'published', published_at: flow.updated_at)
    end

    it 'marks edits even within the same second in index and detail' do
      publication.update!(published_at: flow.updated_at - 0.001.seconds)

      get base_url, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].first['unpublished_changes']).to be true
      get "#{base_url}/#{flow.id}", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['unpublished_changes']).to be true
      get "#{base_url}/#{flow.id}/publication_status", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['unpublished_changes']).to be true
    end

    it 'does not mark a publication equal to or newer than the saved form' do
      publication
      get "#{base_url}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['unpublished_changes']).to be false
      publication.update!(published_at: flow.updated_at + 1.second)
      get "#{base_url}/#{flow.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['unpublished_changes']).to be false
    end

    it 'does not mark a form that has never been published' do
      flow
      get "#{base_url}/#{flow.id}", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['unpublished_changes']).to be false
    end
  end

  describe 'GET index' do
    it 'adds whole-catalog facets while preserving the paginated wrapper and row contract' do
      create_list(:whatsapp_flow, 3, account: account, name: 'Survey', categories: ['SURVEY'])
      get base_url, params: { search: 'Survey', category: 'SURVEY', state: 'none', page: '2', per_page: '1' },
                    headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['payload'].length).to eq(1)
      expect(body['payload'].first).to include('name' => 'Survey', 'categories' => ['SURVEY'], 'publication_summary' => {
                                               'state' => 'none', 'total' => 0, 'published' => 0, 'errors' => 0
                                             })
      expect(body['meta']).to eq('current_page' => 2, 'per_page' => 1, 'total_count' => 3)
      expect(body['facets']['state']).to include('all' => 3, 'none' => 3, 'published' => 0)
      expect(body['facets']['category']).to include('all' => 3, 'SURVEY' => 3, 'OTHER' => 0)
    end

    it 'preserves the payload wrapper for an empty account without WABAs or publications' do
      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('payload' => [])
      expect(response.parsed_body['meta']).to include('total_count' => 0)
    end

    it 'rejects nested filter objects through the real Rails parameter parser' do
      get base_url, params: { search: { value: 'invalid' } }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid')
    end

    it 'paginates and filters by name and category without leaking another account' do
      create(:whatsapp_flow, account: account, name: 'Encuesta uno', categories: ['SURVEY'])
      second = create(:whatsapp_flow, account: account, name: 'Encuesta dos', categories: ['SURVEY'], updated_at: 1.day.ago)
      create(:whatsapp_flow, account: account, name: 'Otro', categories: ['OTHER'])
      create(:whatsapp_flow, name: 'Encuesta ajena', categories: ['SURVEY'])

      get base_url, params: { search: 'Encuesta', category: 'SURVEY', state: 'none', page: '2', per_page: '1' },
                    headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to eq([second.id])
      expect(response.parsed_body['meta']).to eq('current_page' => 2, 'per_page' => 1, 'total_count' => 2)
      expect(response.parsed_body['payload'].first['publication_summary']).to include('state' => 'none', 'total' => 0)
    end

    [{ page: '0' }, { page: '1.5' }, { per_page: '101' }, { state: 'unknown' }, { category: 'UNKNOWN' },
     { search: ['invalid'] }].each do |filters|
      it "rejects invalid catalog filters #{filters.keys.join(', ')}" do
        get base_url, params: filters, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid')
      end
    end

    it 'lists the forms of the account, newest change first, without the definition' do
      older = create(:whatsapp_flow, account: account, name: 'Antiguo', updated_at: 2.days.ago)
      newer = create(:whatsapp_flow, account: account, name: 'Nuevo')
      create(:whatsapp_flow)

      get base_url, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload.pluck('id')).to eq([newer.id, older.id])
      expect(payload.first).to include('name' => 'Nuevo', 'screens' => 1)
      expect(payload.first).not_to have_key('definition')
    end
  end

  describe 'POST create' do
    it 'saves the form as a draft with its definition' do
      post base_url, params: { whatsapp_flow: { name: 'Datos del cliente', categories: %w[LEAD_GENERATION], definition: definition } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('name' => 'Datos del cliente', 'categories' => ['LEAD_GENERATION'], 'screens' => 1)
      expect(body['definition']['screens'][0]['blocks'][1]).to include('type' => 'short_text', 'key' => 'nombre')
      expect(WhatsappFlow.find(body['id'])).to have_attributes(account_id: account.id, created_by_id: admin.id)
    end

    it 'keeps a draft that still has mistakes (the builder shows them), but not one without screens or a name' do
      post base_url, params: { whatsapp_flow: { name: 'Borrador', definition: invalid_definition } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      post base_url, params: { whatsapp_flow: { name: '', definition: definition } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post base_url, params: { whatsapp_flow: { name: 'Sin pantallas', definition: { screens: 'x' } } },
                     headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid')
    end

    it 'refuses a category that Meta does not have' do
      post base_url, params: { whatsapp_flow: { name: 'X', categories: %w[INVENTADA], definition: definition } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH update and DELETE destroy' do
    let!(:flow) { create(:whatsapp_flow, account: account, name: 'Viejo') }

    it 'changes the name and the definition' do
      patch "#{base_url}/#{flow.id}", params: { whatsapp_flow: { name: 'Nuevo nombre', definition: definition } },
                                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(flow.reload.name).to eq('Nuevo nombre')
      expect(flow.definition['screens'][0]['title']).to eq('Tus datos')
    end

    it 'deletes it' do
      delete "#{base_url}/#{flow.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(WhatsappFlow.exists?(flow.id)).to be false
    end
  end

  describe 'POST validate' do
    it 'answers with the Flow JSON of a valid definition, without saving anything' do
      expect do
        post "#{base_url}/validate", params: { definition: definition }, headers: admin.create_new_auth_token, as: :json
      end.not_to change(WhatsappFlow, :count)

      body = response.parsed_body
      expect(body).to include('valid' => true, 'errors' => [])
      expect(body['flow_json']).to include('version' => '7.3')
      expect(body['flow_json']['screens'][0]).to include('id' => 'PANTALLA_A', 'terminal' => true)
    end

    it 'lists the mistakes of an invalid one, each with the place it is in' do
      post "#{base_url}/validate", params: { definition: invalid_definition }, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['valid']).to be false
      expect(body['flow_json']).to be_nil
      expect(body['errors'].pluck('code')).to contain_exactly('screen_title_required', 'key_invalid')
      expect(body['errors'].pluck('path')).to include('screens.0.title', 'screens.0.blocks.0.key')
    end

    it 'treats a missing definition as an empty one' do
      post "#{base_url}/validate", params: {}, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['errors'].pluck('code')).to eq(['screens_required'])
    end
  end
end
