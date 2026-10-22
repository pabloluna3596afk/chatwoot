require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService, '#create' do
  let(:account) { create(:account, locale: 'es') }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:service) { described_class.new(account: account, user: user, connection: connection) }
  let(:body) { 'Hola {{nombre}}, tu cita "{{cita}}" quedó agendada para el {{fecha}} a las {{hora}}. ¿Confirmas tu asistencia?' }
  let(:templates) do
    [{ 'name' => 'cita_confirmacion', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY', 'parameter_format' => 'NAMED',
       'components' => [{ 'type' => 'BODY', 'text' => body }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact) }
  let(:params) do
    { calendar_id: 'cal-1', summary: 'Consulta', start: '2030-01-15T10:00:00-05:00', end: '2030-01-15T10:30:00-05:00',
      contact_id: contact.id, conversation_id: conversation.display_id }
  end

  def google_event_for(id, kwargs)
    { 'id' => id, 'etag' => '"etag-1"', 'summary' => kwargs[:summary], 'start' => { 'dateTime' => kwargs[:start_at].iso8601 },
      'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
  end

  def sent_messages
    conversation.messages.where(message_type: :outgoing)
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) { |**kwargs| google_event_for('g-1', kwargs) }
    allow(client).to receive(:update_event) { |**kwargs| google_event_for(kwargs[:event_id], kwargs) }
    allow(client).to receive(:get_event) do |event_id:, **|
      record = connection.calendar_events.find_by!(google_event_id: event_id)
      google_event_for(event_id, summary: record.summary, start_at: record.start_at, end_at: record.end_at)
    end
  end

  after do
    Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: account.id, calendar_id: 'cal-1'))
    Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: 'g-1'))
  end

  it 'sends the approved confirmation template, with the appointment values, when a person books from the conversation' do
    service.create(params)

    message = sent_messages.last
    expect(message.additional_attributes['template_params']).to include(
      'name' => 'cita_confirmacion', 'language' => 'es', 'category' => 'UTILITY', 'content_mode' => 'rendered',
      'processed_params' => { 'body' => { 'nombre' => 'Ana Pérez', 'cita' => 'Consulta', 'fecha' => '15/01/2030', 'hora' => '10:00' } }
    )
    expect(message.content).to eq('Hola Ana Pérez, tu cita "Consulta" quedó agendada para el 15/01/2030 a las 10:00. ¿Confirmas tu asistencia?')
    expect(message.sender).to eq(user)
  end

  it 'does not render what the contact typed as Liquid' do
    contact.update!(name: '{{ account.name }}')

    service.create(params)

    expect(sent_messages.last.content).to start_with('Hola {{ account.name }},')
  end

  it 'sends it without asking for the notice-only option' do
    expect { service.create(params.merge(send_to_contact: false)) }.to change(sent_messages, :count).by(1)
  end

  it 'does not send it again when the appointment is edited' do
    service.create(params)

    expect { service.update('g-1', params.merge(summary: 'Edited')) }.not_to(change(sent_messages, :count))
  end

  context 'when the template is not approved' do
    let(:templates) { [{ 'name' => 'cita_confirmacion', 'language' => 'es', 'status' => 'PENDING' }] }

    it 'sends nothing, leaves a note in the conversation and still books the appointment' do
      result = I18n.with_locale(:es) { service.create(params) }

      expect(Conversations::ActivityMessageJob).to have_been_enqueued
        .with(conversation, hash_including(content: a_string_including('falta la plantilla')))
      expect(sent_messages.count).to eq(0)
      expect(result[:id]).to eq('g-1')
    end

    it 'keeps the free text when the person asked for the notice only' do
      service.create(params.merge(send_to_contact: true))

      expect(sent_messages.last.content).to include('Consulta')
      expect(sent_messages.last.additional_attributes['template_params']).to be_blank
    end
  end

  context 'when the template does not exist in the channel' do
    let(:templates) { [] }

    it 'sends nothing and leaves the note' do
      I18n.with_locale(:es) { service.create(params) }

      expect(Conversations::ActivityMessageJob).to have_been_enqueued
        .with(conversation, hash_including(content: a_string_including('falta la plantilla')))
      expect(sent_messages.count).to eq(0)
    end
  end

  context 'when the conversation is not WhatsApp Cloud' do
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    it 'sends nothing by default' do
      service.create(params)

      expect(sent_messages.count).to eq(0)
    end

    it 'keeps the free text for the notice-only option' do
      service.create(params.merge(send_to_contact: true))

      expect(sent_messages.last.content).to include('Consulta')
    end
  end

  it 'leaves the confirmation to the Panel AI follow-up when it is enabled' do
    policy = { enabled: true, confirmation: true, reminders_minutes_before: [] }

    expect { service.create(params.merge(bot_followup_policy: policy)) }.to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
    expect(sent_messages.count).to eq(0)
  end

  it 'leaves the confirmation to Captain when Captain books' do
    bot = create(:agent_bot, account: account)

    described_class.new(account: account, user: bot, connection: connection).create(params)

    expect(sent_messages.count).to eq(0)
  end

  it 'never breaks the booking when the notice fails' do
    allow_any_instance_of(Integrations::GoogleCalendar::CustomerNotice).to receive(:deliver!).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

    expect(service.create(params)[:id]).to eq('g-1')
  end
end
