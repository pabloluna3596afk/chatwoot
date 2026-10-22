require 'rails_helper'

RSpec.describe 'Calendar activation kit API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/activation_kit" }
  let(:service) { instance_double(Whatsapp::TemplateManagementService, create: { id: '1', status: 'PENDING' }) }

  before { allow(Calendar::AppointmentAttributes::BackfillJob).to receive(:perform_later) }

  it 'requires authentication' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'shows the kit to agents' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['template']).to include('name' => 'cita_confirmacion', 'language' => 'es',
                                                                         'buttons' => %w[Confirmar Reagendar Cancelar])
    expect(response.parsed_body['inboxes']).to eq([])
  end

  it 'only lets administrators apply it' do
    patch url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'applies the kit to the chosen inboxes of the account' do
    allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(service)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false, message_templates: [])
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    patch url, params: { inbox_ids: [channel.inbox.id, other.inbox.id] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['results'].keys).to eq([channel.inbox.id.to_s])
    expect(service).to have_received(:create).once
  end
end
