require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants appointments settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  let(:reminder_defaults) do
    { reminder_1: { enabled: true, hours_before: 24 }, reminder_2: { enabled: true, hours_before: 3 },
      template_confirmation: nil, template_reminder: nil, template_cancelled: nil }
  end

  before { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }

  it 'returns the defaults, disabled, for an assistant that never configured appointments' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:appointments]).to eq(
      enabled: false, calendar_connection_id: nil, calendar_id: nil, slot_duration_minutes: 30,
      required_contact_fields: %w[name phone email], min_notice_minutes: 60, booking_window_days: 14, **reminder_defaults
    )
  end

  it 'saves the appointments settings' do
    settings = {
      enabled: true, calendar_connection_id: connection.id, calendar_id: 'cal-1', slot_duration_minutes: 45,
      required_contact_fields: %w[name phone], min_notice_minutes: 120, booking_window_days: 30
    }

    patch url, params: { assistant: { config: { appointments: settings } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:appointments]).to eq(settings.merge(reminder_defaults))
    expect(assistant.reload.appointments).to be_enabled
  end

  it 'saves the two reminders with their own lead time' do
    settings = { reminder_1: { enabled: false, hours_before: 48 }, reminder_2: { enabled: true, hours_before: 6 } }

    patch url, params: { assistant: { config: { appointments: settings } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:appointments]).to include(settings)
    expect(assistant.reload.appointments).to have_attributes(any_reminder_enabled?: true)
    expect(assistant.appointments.hours_before('reminder_2')).to eq(6)
  end

  it 'rejects lead times outside 1 to 168 hours' do
    [0, 169].each do |hours|
      patch url, params: { assistant: { config: { appointments: { reminder_1: { enabled: true, hours_before: hours } } } } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity), "#{hours} h should be rejected"
    end
  end

  context 'with a WhatsApp template that has variables' do
    let(:templates) do
      [{ 'name' => 'cita', 'language' => 'es', 'status' => 'approved',
         'components' => [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Cita {{titulo}}' },
                          { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, es el {{fecha}}.' }] }]
    end
    let(:params) do
      { header: { titulo: '{{ appointment.title }}' }, body: { nombre: '{{ contact.name }}', fecha: '{{ appointment.date }}' } }
    end

    before do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                message_templates: templates)
    end

    def save_template(processed_params)
      patch url, params: { assistant: { config: { appointments: { template_reminder: { name: 'cita', language: 'es',
                                                                                      processed_params: processed_params } } } } },
            headers: admin.create_new_auth_token, as: :json
    end

    it 'saves the template with a text for every variable of the body and the header' do
      save_template(params)

      expect(response).to have_http_status(:success)
      expect(assistant.reload.appointments.template_reminder['processed_params']).to eq(
        'header' => { 'titulo' => '{{ appointment.title }}' },
        'body' => { 'nombre' => '{{ contact.name }}', 'fecha' => '{{ appointment.date }}' }
      )
    end

    it 'cannot be saved with a variable left empty' do
      save_template(params.merge(body: { nombre: '{{ contact.name }}', fecha: ' ' }))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(assistant.reload.appointments.template_reminder).to be_nil
    end

    it 'cannot be saved with a variable left out' do
      save_template(params.merge(body: { nombre: '{{ contact.name }}' }))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'cannot be saved with no texts at all' do
      patch url, params: { assistant: { config: { appointments: { template_reminder: { name: 'cita', language: 'es' } } } } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'cannot be saved with a text that is not valid Liquid' do
      save_template(params.merge(body: { nombre: '{% if %}', fecha: '{{ appointment.date }}' }))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'accepts a fixed text, which is just a text without Liquid' do
      save_template(params.merge(body: { nombre: '{{ contact.name }}', fecha: 'pronto' }))

      expect(response).to have_http_status(:success)
    end
  end

  it 'rejects a template without a language' do
    patch url, params: { assistant: { config: { appointments: { template_reminder: { name: 'recordatorio' } } } } },
          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps the settings when another form saves the config it received' do
    assistant.update!(config: assistant.config.merge(
      'appointments' => { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }
    ))
    get url, headers: admin.create_new_auth_token, as: :json
    received = json_response[:config]

    patch url, params: { assistant: { config: received.merge(response_window: 'always') } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(assistant.reload.appointments).to be_enabled
    expect(assistant.appointments.calendar_id).to eq('cal-1')
  end

  it 'rejects enabling appointments without a valid calendar' do
    patch url, params: { assistant: { config: { appointments: { enabled: true } } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.appointments).not_to be_enabled
  end

  it 'rejects a calendar connection of another account' do
    other = CalendarConnection.create!(account: create(:account), provider: 'google', email: 'other@example.com', refresh_token: 'r')

    patch url, params: { assistant: { config: { appointments: { enabled: true, calendar_connection_id: other.id, calendar_id: 'cal-1' } } } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
