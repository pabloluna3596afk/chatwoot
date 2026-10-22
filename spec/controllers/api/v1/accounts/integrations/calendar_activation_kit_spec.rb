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
    expect(response.parsed_body['template']).to include('name' => 'cita_confirmacion', 'language' => 'es')
    expect(response.parsed_body['template']['buttons']).to eq(%w[Confirmar Reagendar Cancelar])
    expect(response.parsed_body['cancel_template']).to include('name' => 'cita_cancelacion', 'language' => 'es')
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
    expect(response.parsed_body['inboxes'].first).to include('cancel_status' => 'missing', 'cancel_rejected_reason' => nil)
    expect(service).to have_received(:create).exactly(3).times
    expect(response.parsed_body['results'][channel.inbox.id.to_s]).to include(
      'status' => 'pending', 'cancel' => { 'status' => 'pending' }, 'reminder' => { 'status' => 'pending' }
    )
  end

  it 'exposes the switch off by default and the third template' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['reminder_enabled']).to be(false)
    expect(response.parsed_body['reminder_template']).to include('name' => 'cita_recordatorio')
  end

  [true, false].each do |enabled|
    it "lets administrators save reminder_enabled #{enabled} without submitting the kit" do
      account.update!(settings: { 'reporting_timezone' => 'UTC' })
      patch url, params: { reminder_enabled: enabled }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(account.reload.customer_reminders_enabled).to be(enabled)
      expect(account.reporting_timezone).to eq('UTC')
      expect(response.parsed_body['reminder_enabled']).to be(enabled)
      expect(Calendar::AppointmentAttributes::BackfillJob).not_to have_received(:perform_later)
    end
  end

  it 'forbids agents from changing the reminder switch' do
    patch url, params: { reminder_enabled: true }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.customer_reminders_enabled).to be_nil
  end

  ['true', 1, nil, [], {}].each do |invalid|
    it "rejects malformed switch input #{invalid.inspect}" do
      patch url, params: { reminder_enabled: invalid }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.customer_reminders_enabled).to be_nil
    end
  end
end
