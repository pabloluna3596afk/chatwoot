require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService do
  let(:account) { create(:account, name: 'Clínica Sol', locale: 'es') }
  let(:user) { create(:user, account: account, role: :administrator, name: 'Pablo Luna') }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:service) { described_class.new(account: account, user: user, connection: connection) }
  let(:created_calls) { [] }
  let(:meet_url) { 'https://meet.google.com/abc-defg-hij' }

  # Guayaquil is UTC-5 all year, the fallback timezone when the account has none.
  let(:slot_start) { '2030-01-15T10:00:00-05:00' }
  let(:slot_end) { '2030-01-15T10:30:00-05:00' }

  def google_event_for(id, kwargs)
    {
      'id' => id, 'etag' => '"etag-1"', 'summary' => kwargs[:summary], 'htmlLink' => 'https://calendar.test/event',
      'description' => kwargs[:description],
      'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 }
    }
  end

  def params(overrides = {})
    { calendar_id: 'cal-1', summary: 'Consulta', start: slot_start, end: slot_end, contact_id: contact.id }.merge(overrides)
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      created_calls << kwargs
      google_event_for("g-#{created_calls.size}", kwargs)
    end
    allow(client).to receive(:update_event) { |**kwargs| google_event_for(kwargs[:event_id], kwargs) }
    allow(client).to receive(:update_description)
  end

  after do
    Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: account.id, calendar_id: 'cal-1'))
    %w[g-1 g-2].each { |id| Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: id)) }
  end

  it 'uses the default text, friendly to the customer, with this appointment\'s values' do
    service.create(params)

    description = created_calls.first[:description]
    expect(description).to include('Hola Ana, te esperamos en tu cita con Pablo Luna de Clínica Sol.')
    expect(description).to include('Fecha: martes 15 de enero', 'Hora: 10:00')
    expect(description).to include('Si necesitas cambiar la cita, responde a este mensaje.')
    expect(description).not_to include('Cita InboxHub')
  end

  it 'leaves out the place and the video call while the account has no address and the appointment no Meet' do
    service.create(params)

    expect(created_calls.first[:description]).not_to include('Lugar')
    expect(created_calls.first[:description]).not_to include('Videollamada')
  end

  it 'uses the text and the address the account wrote' do
    account.update!(appointment_invitation_template: 'Te esperamos, {{nombre}}. {{motivo}} en {{direccion}}.', appointment_location: 'Av. Sol 1')

    service.create(params)

    expect(created_calls.first[:description]).to eq('Te esperamos, Ana Pérez. Consulta en Av. Sol 1.')
  end

  it 'names the assistant as the agent when Captain books' do
    assistant = Struct.new(:name).new('Aurora')
    captain = described_class.new(account: account, user: assistant, connection: connection)

    captain.create(params)

    expect(created_calls.first[:description]).to include('con Aurora de Clínica Sol')
  end

  describe 'a text written for one appointment' do
    it 'is used instead of the account text, with its variables filled in, and kept with the appointment' do
      service.create(params(description: 'Hola {{primer_nombre}}, trae tu cédula.'))

      expect(created_calls.first[:description]).to eq('Hola Ana, trae tu cédula.')
      expect(CalendarEvent.find_by(google_event_id: 'g-1').invitation_text).to eq('Hola {{primer_nombre}}, trae tu cédula.')
    end

    it 'follows a change of the appointment: the variables are filled in again, the text stays' do
      service.create(params(description: 'Te esperamos el {{fecha}}.'))

      service.update('g-1', params(start: '2030-01-16T10:00:00-05:00', end: '2030-01-16T10:30:00-05:00', etag: '"etag-1"'))

      expect(client).to have_received(:update_event).with(hash_including(description: 'Te esperamos el miércoles 16 de enero.'))
      expect(CalendarEvent.find_by(google_event_id: 'g-1').invitation_text).to eq('Te esperamos el {{fecha}}.')
    end

    it 'is replaced by a new one and cleared by an empty one' do
      service.create(params(description: 'Uno'))

      service.update('g-1', params(description: 'Dos', etag: '"etag-1"'))
      expect(CalendarEvent.find_by(google_event_id: 'g-1').invitation_text).to eq('Dos')

      service.update('g-1', params(description: '', etag: '"etag-1"'))
      expect(CalendarEvent.find_by(google_event_id: 'g-1').invitation_text).to be_nil
      expect(client).to have_received(:update_event).with(hash_including(description: include('Hola Ana')))
    end

    it 'does not touch the account text of other appointments' do
      service.create(params(description: 'Solo esta'))
      service.create(params(start: '2030-01-16T10:00:00-05:00', end: '2030-01-16T10:30:00-05:00'))

      expect(created_calls.last[:description]).to include('te esperamos en tu cita')
    end
  end

  describe 'the Meet link' do
    def with_meet(link)
      allow(client).to receive(:create_event) do |**kwargs|
        created_calls << kwargs
        google_event_for('g-1', kwargs).merge('conferenceData' => { 'entryPoints' => [{ 'entryPointType' => 'video', 'uri' => link }] })
      end
    end

    it 'is written into the invitation once Google has created it, when the text uses it' do
      with_meet(meet_url)

      service.create(params(include_meet: true))

      expect(created_calls.first[:description]).not_to include('Videollamada')
      expect(client).to have_received(:update_description)
        .with(calendar_id: 'cal-1', event_id: 'g-1', description: include("Videollamada: #{meet_url}"))
    end

    it 'does not call Google again when the text does not use it' do
      account.update!(appointment_invitation_template: 'Hola {{nombre}}')
      with_meet(meet_url)

      service.create(params(include_meet: true))

      expect(client).not_to have_received(:update_description)
    end

    it 'does not call Google again when the event has no Meet link' do
      service.create(params)

      expect(client).not_to have_received(:update_description)
    end
  end
end
