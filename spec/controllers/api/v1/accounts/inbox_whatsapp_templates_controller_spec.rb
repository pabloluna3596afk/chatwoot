require 'rails_helper'

RSpec.describe 'Inbox WhatsApp templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_templates" }
  let(:service) { instance_double(Whatsapp::TemplateManagementService) }
  let(:template) do
    { name: 'recordatorio_cita', language: 'es', category: 'UTILITY',
      header: { format: 'NONE' }, body: { text: 'Hola {{1}}, tu cita es el {{2}}.', examples: %w[Ana lunes] },
      footer: { text: 'Gracias' }, buttons: [{ type: 'QUICK_REPLY', text: 'Confirmar' }] }
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(service)
  end

  describe 'who can manage templates' do
    it 'requires authentication' do
      post base_url, params: { template: template }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses agents on every action (they use templates, they do not manage them)' do
      headers = agent.create_new_auth_token

      post base_url, params: { template: template }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{base_url}/555", params: { template: template }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{base_url}/555", params: { name: 'recordatorio_cita' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      get "#{base_url}/555", headers: headers
      expect(response).to have_http_status(:unauthorized)
      get "#{base_url}/capabilities", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it 'only works on WhatsApp Cloud inboxes' do
      web = create(:channel_widget, account: account).inbox

      post "/api/v1/accounts/#{account.id}/inboxes/#{web.id}/whatsapp_templates", params: { template: template },
                                                                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('cloud_channel_required')
    end
  end

  describe 'POST create' do
    it 'builds the components and creates the template in Meta' do
      allow(service).to receive(:create).and_return(id: '999', status: 'PENDING', category: 'UTILITY')

      post base_url, params: { template: template }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('id' => '999', 'status' => 'PENDING')
      expect(service).to have_received(:create).with(
        name: 'recordatorio_cita', language: 'es', category: 'UTILITY', parameter_format: 'POSITIONAL',
        components: [
          { type: 'BODY', text: 'Hola {{1}}, tu cita es el {{2}}.', example: { body_text: [%w[Ana lunes]] } },
          { type: 'FOOTER', text: 'Gracias' },
          { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'Confirmar' }] }
        ]
      )
    end

    it 'creates a named template (the default for new ones) and tells Meta its format' do
      allow(service).to receive(:create).and_return(id: '999', status: 'PENDING', category: 'UTILITY')
      named = template.merge(body: { text: 'Hola {{nombre}}, tu cita es el {{fecha}}.', examples: %w[Ana lunes] }, buttons: [])

      post base_url, params: { template: named }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(service).to have_received(:create).with(
        hash_including(
          parameter_format: 'NAMED',
          components: array_including(
            { type: 'BODY', text: 'Hola {{nombre}}, tu cita es el {{fecha}}.',
              example: { body_text_named_params: [{ param_name: 'nombre', example: 'Ana' }, { param_name: 'fecha', example: 'lunes' }] } }
          )
        )
      )
    end

    it 'refuses a name, language or category Meta would not accept, without calling Meta' do
      allow(service).to receive(:create)

      [{ name: 'Con Espacio' }, { language: 'español' }, { category: 'AUTHENTICATION' }].each do |change|
        post base_url, params: { template: template.merge(change) }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(service).not_to have_received(:create)
    end

    it 'answers a form mistake with its code and a Spanish message' do
      allow(service).to receive(:create)

      post base_url, params: { template: template.merge(body: { text: 'Hola {{1}}', examples: [] }) },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('variable_at_edge')
      expect(response.parsed_body['message']).to be_present
    end

    it 'returns the original Meta message, code, subcode and user message' do
      error = Whatsapp::TemplateManagementService::Error.new('meta_error', meta_message: 'Invalid parameter', meta_code: 100,
                                                                           error_subcode: 123, error_user_msg: 'No se permite editar')
      allow(service).to receive(:create).and_raise(error)
      post base_url, params: { template: template }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('message' => 'Invalid parameter', 'code' => 100, 'error_subcode' => 123,
                                              'error_user_msg' => 'No se permite editar')
    end

    it 'answers what Meta refuses with a plain message' do
      allow(service).to receive(:create).and_raise(Whatsapp::TemplateManagementService::Error.new('name_locked', meta_code: 100))

      post base_url, params: { template: template }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'name_locked')
      expect(response.parsed_body['message']).to include('30')
    end
  end

  describe 'PATCH update' do
    it 'edits through the template id' do
      allow(service).to receive(:update).and_return(id: '555', status: 'PENDING')

      patch "#{base_url}/555", params: { template: template.slice(:body, :footer) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(service).to have_received(:update).with('555', components: anything, category: nil)
    end
  end

  describe 'PATCH edit with the real service and Meta responses' do
    let(:graph) { "https://graph.facebook.com/#{Whatsapp::TemplateManagementService::API_VERSION}" }
    let(:original) do
      { id: '555', name: 'test_utility_envio', language: 'es_EC', category: 'UTILITY', status: 'APPROVED',
        parameter_format: 'POSITIONAL', components: [
          { type: 'BODY', text: 'Hola {{1}}, pedido {{2}}, fecha {{3}}, agente {{4}}.', example: { body_text: [%w[Ana 123 lunes Luis]] } },
          { type: 'BUTTONS', buttons: [{ type: 'URL', text: 'Seguir', url: 'https://paluhub.com/track/{{2}}',
                                         example: ['https://paluhub.com/track/123'] }] }
        ] }
    end
    let(:edit_form) do
      { name: original[:name], language: 'es_EC', parameter_format: 'POSITIONAL', header: { format: 'NONE' },
        body: { text: original[:components].first[:text], examples: %w[Ana 123 lunes Luis] }, footer: { text: '' },
        buttons: [{ type: 'URL', text: 'Seguir', url: 'https://paluhub.com/track/{{2}}', examples: ['https://paluhub.com/track/123'] }] }
    end

    before do
      allow(Whatsapp::TemplateManagementService).to receive(:new).and_call_original
      stub_request(:get, "#{graph}/555").with(query: { fields: Whatsapp::TemplateManagementService::FIELDS })
                                        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: original.to_json)
    end

    it 'passes the complete original structure to Meta and returns every error field' do
      allow(Rails.logger).to receive(:warn)
      edit = stub_request(:post, "#{graph}/555").with(body: { components: original[:components] }.to_json)
                                                .to_return(status: 400, headers: { 'Content-Type' => 'application/json' }, body: {
                                                  error: { message: 'Invalid parameter', code: 100, error_subcode: 123,
                                                           error_user_msg: 'Solo una edición cada 24 horas' }
                                                }.to_json)
      patch "#{base_url}/555", params: { template: edit_form }, headers: admin.create_new_auth_token, as: :json

      expect(edit).to have_been_requested.once
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('message' => 'Invalid parameter', 'code' => 100, 'error_subcode' => 123,
                                              'error_user_msg' => 'Solo una edición cada 24 horas')
      expect(Rails.logger).to have_received(:warn).with(include('template=test_utility_envio HTTP 400'))
      expect(Rails.logger).not_to have_received(:warn).with(include(channel.template_access_token))
    end

    it 'blocks new components and parameter format changes before posting to Meta' do
      [edit_form.merge(header: { format: 'TEXT', text: 'Hola' }), edit_form.merge(parameter_format: 'NAMED')].each do |changed|
        patch "#{base_url}/555", params: { template: changed }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to match(/edit_(structure|identity)_locked|variables_mixed/)
      end
      expect(a_request(:post, "#{graph}/555")).not_to have_been_made
    end
  end

  describe 'DELETE destroy' do
    it 'deletes by hsm_id and name' do
      allow(service).to receive(:delete).and_return(deleted: true)

      delete "#{base_url}/555", params: { name: 'recordatorio_cita' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(service).to have_received(:delete).with(name: 'recordatorio_cita', hsm_id: '555')
    end

    it 'needs the name' do
      allow(service).to receive(:delete)

      delete "#{base_url}/555", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(service).not_to have_received(:delete)
    end
  end

  describe 'GET show and capabilities' do
    it 'returns the live state' do
      allow(service).to receive(:fetch).with('555').and_return(id: '555', status: 'REJECTED', rejected_reason: 'INVALID_FORMAT')

      get "#{base_url}/555", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'REJECTED', 'rejected_reason' => 'INVALID_FORMAT')
    end

    it 'says whether the channel can use media headers' do
      handles = instance_double(Whatsapp::TemplateHeaderHandleService, available?: false, unavailable_reason: 'upload_refused')
      allow(Whatsapp::TemplateHeaderHandleService).to receive(:new).and_return(handles)

      get "#{base_url}/capabilities", headers: admin.create_new_auth_token

      expect(response.parsed_body).to eq('media_header' => false, 'reason' => 'upload_refused')
    end
  end

  describe 'POST header_handle' do
    let(:png) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

    it 'uploads the example file and returns the handle' do
      handles = instance_double(Whatsapp::TemplateHeaderHandleService, upload!: '4::handle')
      allow(Whatsapp::TemplateHeaderHandleService).to receive(:new).and_return(handles)

      post "#{base_url}/header_handle", params: { header_format: 'IMAGE', file: png }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('handle' => '4::handle', 'format' => 'IMAGE', 'name' => 'avatar.png')
    end

    it 'refuses a file the header does not accept' do
      post "#{base_url}/header_handle", params: { header_format: 'DOCUMENT', file: png }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('file_invalid_type')
    end

    it 'says so when the channel cannot upload examples' do
      handles = instance_double(Whatsapp::TemplateHeaderHandleService)
      allow(handles).to receive(:upload!).and_raise(Whatsapp::TemplateHeaderHandleService::Error, 'media_header_unavailable')
      allow(Whatsapp::TemplateHeaderHandleService).to receive(:new).and_return(handles)

      post "#{base_url}/header_handle", params: { header_format: 'IMAGE', file: png }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('media_header_unavailable')
    end
  end

  describe 'the Meta library' do
    it 'lists it with the filters' do
      allow(service).to receive(:library).and_return(templates: [{ 'name' => 'appointment_reminder' }], next: 'abc', language_used: 'es')

      get "#{base_url}/library", params: { search: 'cita', language: 'es_EC', after: 'previous' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['templates'].first['name']).to eq('appointment_reminder')
      expect(response.parsed_body).to include('language_used' => 'es', 'next' => 'abc')
      expect(service).to have_received(:library).with(search: 'cita', language: 'es_EC', after: 'previous')
    end

    it 'creates a template from it' do
      allow(service).to receive(:create_from_library).and_return(id: '7', status: 'APPROVED', category: 'UTILITY', language_used: 'es')

      post "#{base_url}/library", params: { library_template: { library_template_name: 'appointment_reminder', name: 'recordatorio',
                                                                language: 'es_EC', category: 'UTILITY' } },
                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['language_used']).to eq('es')
      expect(service).to have_received(:create_from_library).with(
        library_template_name: 'appointment_reminder', name: 'recordatorio', language: 'es_EC', category: 'UTILITY'
      )
    end

    it 'returns the real Meta error from the library' do
      error = Whatsapp::TemplateManagementService::Error.new('meta_error', detail: 'Invalid topic', meta_code: 100, http_status: 400)
      allow(service).to receive(:library).and_raise(error)

      get "#{base_url}/library", params: { language: 'es_EC' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'meta_error', 'message' => 'Invalid topic', 'meta_code' => 100)
    end

    it 'returns the real Meta user message when creation fails' do
      error = Whatsapp::TemplateManagementService::Error.new('name_exists', detail: 'Este nombre ya existe.', meta_code: 100)
      allow(service).to receive(:create_from_library).and_raise(error)

      post "#{base_url}/library", params: { library_template: { library_template_name: 'appointment_reminder', name: 'recordatorio',
                                                                language: 'es_EC', category: 'UTILITY' } },
                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'name_exists', 'message' => 'Este nombre ya existe.', 'meta_code' => 100)
    end

    it 'preserves the status mapping for rate errors' do
      error = Whatsapp::TemplateManagementService::Error.new('rate_limited', detail: 'Too many requests', meta_code: 4)
      allow(service).to receive(:library).and_raise(error)

      get "#{base_url}/library", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['message']).to eq('Too many requests')
    end

    it 'refuses authentication templates and bad names, and agents' do
      allow(service).to receive(:create_from_library)
      attributes = { library_template_name: 'x', name: 'ok_name', language: 'es', category: 'AUTHENTICATION' }

      post "#{base_url}/library", params: { library_template: attributes }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{base_url}/library", params: { library_template: attributes.merge(category: 'UTILITY') }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "#{base_url}/library", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(service).not_to have_received(:create_from_library)
    end
  end
end
