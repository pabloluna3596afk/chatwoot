require 'rails_helper'

RSpec.shared_context 'with an appointments conversation' do
  let(:account) { create(:account, locale: 'es') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now
    )
  end
  let!(:calendar) { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }
  let(:appointments_config) do
    { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }
  end
  let(:assistant) do
    create(:captain_assistant, account: account, name: 'Asistente de Ventas', config: { 'appointments' => appointments_config })
  end
  let(:inbox) { create(:inbox, account: account) }
  let!(:captain_inbox) { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }
  let(:contact_attributes) { { name: 'Ana Pérez', email: 'ana@example.com', phone_number: '+593991234567' } }
  let(:contact) { create(:contact, { account: account }.merge(contact_attributes)) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:tool) { described_class.new(assistant) }

  def local_event(attrs = {})
    connection.calendar_events.create!(
      {
        account: account, external_calendar_id: 'cal-1', google_event_id: "local-#{SecureRandom.hex(4)}", summary: 'Existing',
        start_at: Time.zone.parse('2030-01-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:30:00-05:00')
      }.merge(attrs)
    )
  end

  # Monday 2030-01-14 12:00 in Guayaquil (UTC-5, the fallback account timezone).
  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00-05:00')) { example.run } }

  before do
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      { 'id' => 'g-1', 'etag' => '"e"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
    allow(client).to receive(:update_event) do |**kwargs|
      { 'id' => kwargs[:event_id], 'etag' => '"e2"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
    allow(client).to receive(:delete_event).and_return({})
  end

  after do
    %w[g-1 own-1 other-1].each do |event_id|
      Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: event_id))
    end
    Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: account.id, calendar_id: 'cal-1'))
    Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_QUICK_REPLIES, conversation_id: conversation.id))
    Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_QUICK_REPLY_CHOICES, conversation_id: conversation.id))
  end
end

RSpec.shared_examples 'an appointment tool that needs the channel enabled' do
  it 'does nothing when the inbox switched appointments off' do
    captain_inbox.update!(appointments_enabled: false)

    expect(call).to include('no están disponibles en este canal')
    expect(client).not_to have_received(:list_events)
    expect(client).not_to have_received(:create_event)
  end

  it 'does nothing when the assistant has appointments off' do
    assistant.update!(config: assistant.config.merge('appointments' => appointments_config.merge('enabled' => false)))

    expect(call).to include('no están disponibles en este canal')
  end

  it 'does nothing for an inbox the assistant is not connected to' do
    captain_inbox.destroy!

    expect(call).to include('no están disponibles en este canal')
  end

  it 'answers in the account language' do
    account.update!(locale: 'en')
    captain_inbox.update!(appointments_enabled: false)

    expect(call).to include('Appointments are not available in this channel')
  end

  it 'does not fail when the conversation is unknown' do
    allow(tool).to receive(:find_conversation).and_return(nil)

    expect(call).to eq('Conversation not found')
  end
end

RSpec.describe Captain::Tools::CheckAvailabilityTool do
  include_context 'with an appointments conversation'

  def call(**params)
    tool.perform(tool_context, **params)
  end

  def option_lines(result)
    result.lines.grep(/\A- /)
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'lists free times with the exact start value, in the account language and timezone' do
    result = call(from_date: '2030-01-15', to_date: '2030-01-15')

    expect(result.lines.first).to include('Horarios libres', 'America/Guayaquil')
    expect(result).to include('- martes 15/01 08:00 (start=2030-01-15T08:00:00-05:00)')
    expect(result).to include('- martes 15/01 14:00 (start=2030-01-15T14:00:00-05:00)')
    expect(result.lines.last).to include('botones')
  end

  context 'with a channel that renders buttons' do
    it 'stashes one button per option, titled short and valued with the exact start' do
      call(from_date: '2030-01-15', to_date: '2030-01-15')

      expect(Captain::QuickReplies.take(conversation)).to eq(
        [{ 'title' => 'mar 15/01 · 08:00', 'value' => 'mar 15/01 · 08:00' },
         { 'title' => 'mar 15/01 · 14:00', 'value' => 'mar 15/01 · 14:00' }]
      )
    end

    it 'remembers which exact start each readable button stands for' do
      call(from_date: '2030-01-15', to_date: '2030-01-15')

      expect(Captain::QuickReplies.choice(conversation, 'mar 15/01 · 08:00')).to eq('start' => '2030-01-15T08:00:00-05:00')
      expect(Captain::QuickReplies.choice(conversation, 'mar 15/01 · 14:00')).to eq('start' => '2030-01-15T14:00:00-05:00')
    end

    it 'keeps every title within the WhatsApp button limit' do
      call(from_date: '2030-01-15', to_date: '2030-01-25')

      titles = Captain::QuickReplies.take(conversation).pluck('title')
      expect(titles.size).to eq(6)
      expect(titles.map(&:length).max).to be <= 20
    end

    it 'tags the buttons with the customer message being answered' do
      state = { conversation: { id: conversation.id }, responding_to_message_id: 77 }

      tool.perform(Struct.new(:state).new(state), from_date: '2030-01-15', to_date: '2030-01-15')

      expect(Captain::QuickReplies.take(conversation, responding_to: 76)).to be_nil
      tool.perform(Struct.new(:state).new(state), from_date: '2030-01-15', to_date: '2030-01-15')
      expect(Captain::QuickReplies.take(conversation, responding_to: 77)).to be_present
    end

    it 'sends no buttons when nothing is free' do
      calendar.update!(working_days: [0])

      call(from_date: '2030-01-15', to_date: '2030-01-16')

      expect(Captain::QuickReplies.take(conversation)).to be_nil
    end
  end

  context 'with a channel that has no buttons' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

    it 'numbers the options, keeps the start values and asks for the number' do
      result = call(from_date: '2030-01-15', to_date: '2030-01-15')

      expect(result).to include('1. martes 15/01 08:00 (start=2030-01-15T08:00:00-05:00)', '2. martes 15/01 14:00')
      expect(result.lines.last).to include('lista numerada', 'número')
      expect(Captain::QuickReplies.take(conversation)).to be_nil
    end
  end

  it 'offers at most six options spread over the days' do
    lines = option_lines(call(from_date: '2030-01-15', to_date: '2030-01-25'))

    expect(lines.size).to eq(6)
    expect(lines.map { |line| line[/\d{2}\/\d{2}/] }.uniq.size).to eq(3)
  end

  it 'starts today after the minimum notice and never offers past times' do
    lines = option_lines(call)

    expect(lines.first).to include('start=2030-01-14T13:00:00-05:00')
    expect(lines.join).not_to include('start=2030-01-14T12:')
  end

  it 'does not look past the booking window' do
    lines = option_lines(call(from_date: '2030-01-27', to_date: '2030-03-01'))

    expect(lines.join).to include('2030-01-27')
    expect(lines.join).not_to include('2030-01-29')
  end

  it 'skips busy times' do
    local_event(start_at: Time.zone.parse('2030-01-15T08:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T09:00:00-05:00'))

    result = call(from_date: '2030-01-15', to_date: '2030-01-15')

    expect(result).not_to include('start=2030-01-15T08:00:00-05:00')
    expect(result).to include('start=2030-01-15T09:00:00-05:00')
  end

  it 'says there is nothing free when the period has no working day' do
    calendar.update!(working_days: [0])

    expect(call(from_date: '2030-01-15', to_date: '2030-01-16')).to include('No hay horarios libres')
  end

  it 'asks for a readable date' do
    expect(call(from_date: 'mañana')).to include('AAAA-MM-DD')
  end

  it 'relays a calendar failure as a short message, never a stack trace' do
    allow(client).to receive(:list_events).and_raise(Integrations::GoogleCalendar::Client::Error.new('boom', code: 500))

    result = call(from_date: '2030-01-15', to_date: '2030-01-15')

    expect(result).to include('No se pudo acceder al calendario')
    expect(result).not_to include('boom')
  end
end

RSpec.describe Captain::Tools::BookAppointmentTool do
  include_context 'with an appointments conversation'

  let(:start) { '2030-01-15T10:00:00-05:00' }

  def call(**params)
    tool.perform(tool_context, **{ start: start, customer_confirmed: true }.merge(params))
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'books the confirmed time as an AI booking tied to the conversation and the contact' do
    result = call

    expect(result).to eq('Agendada: martes 15/01 10:00. El cliente recibirá una invitación de calendario en ana@example.com.')
    event = CalendarEvent.find_by(google_event_id: 'g-1')
    expect(event).to have_attributes(
      booking_source: 'ai', contact_id: contact.id, conversation_id: conversation.id, summary: 'Cita con Ana Pérez',
      appointment_status: 'none', bot_followup_policy: {}, created_by_id: nil
    )
    expect(event.idempotency_key).to start_with('captain-')
  end

  it 'sends the invitation to the contact email and uses the assistant slot length' do
    call

    expect(client).to have_received(:create_event) do |**kwargs|
      expect(kwargs).to include(calendar_id: 'cal-1', attendee_email: 'ana@example.com', summary: 'Cita con Ana Pérez')
      expect(kwargs[:end_at] - kwargs[:start_at]).to eq(30.minutes.to_i)
    end
  end

  it 'uses the reason as the title when the model passes one' do
    call(reason: 'Revisión del plan')

    expect(CalendarEvent.find_by(google_event_id: 'g-1').summary).to eq('Revisión del plan')
  end

  it 'never sets a bot follow-up policy, so Panel AI is not notified' do
    expect { call }.not_to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
  end

  context 'without the customer explicit confirmation' do
    it 'does not book and tells the model to ask first' do
      [false, nil, 'false', 'no'].each do |value|
        expect(call(customer_confirmed: value)).to include('customer_confirmed true')
      end
      expect(client).not_to have_received(:create_event)
      expect(CalendarEvent.count).to eq(0)
    end

    it 'accepts the string true' do
      expect(call(customer_confirmed: 'true')).to start_with('Agendada')
    end
  end

  context 'when contact details are missing' do
    let(:contact_attributes) { { name: 'Ana Pérez', email: nil, phone_number: nil } }

    it 'asks only for what the contact lacks and books nothing yet' do
      result = call

      expect(result).to include('teléfono, correo electrónico')
      expect(result).not_to include('nombre')
      expect(client).not_to have_received(:create_event)
    end

    it 'saves what the model passes and then books' do
      result = call(phone: '+593 99 123 4567', email: 'Ana@Example.com')

      expect(result).to start_with('Agendada')
      expect(contact.reload).to have_attributes(phone_number: '+593991234567', email: 'ana@example.com')
    end

    it 'asks again for a detail that is still missing' do
      expect(call(email: 'ana@example.com')).to include('teléfono')
      expect(contact.reload.email).to eq('ana@example.com')
    end

    it 'asks the customer to confirm a phone that is not valid' do
      result = call(phone: '0991234567', email: 'ana@example.com')

      expect(result).to include('No se pudieron guardar', 'teléfono')
      expect(CalendarEvent.count).to eq(0)
    end
  end

  context 'when the contact already has the details' do
    it 'never overwrites them with what the model passes' do
      call(name: 'Otra Persona', email: 'otra@example.com', phone: '+593900000000')

      expect(contact.reload).to have_attributes(name: 'Ana Pérez', email: 'ana@example.com', phone_number: '+593991234567')
    end
  end

  context 'when the assistant only requires some details' do
    let(:appointments_config) do
      { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1', 'required_contact_fields' => ['name'] }
    end
    let(:contact_attributes) { { name: 'Ana Pérez', email: nil, phone_number: nil } }

    it 'books without asking for the rest' do
      expect(call).to eq('Agendada: martes 15/01 10:00.')
    end
  end

  context 'when the time cannot be booked' do
    it 'says the time was taken when another event overlaps it' do
      local_event(start_at: Time.zone.parse('2030-01-15T10:15:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:45:00-05:00'))

      expect(call).to include('ya no está disponible')
      expect(client).not_to have_received(:create_event)
    end

    it 'says the time is outside the calendar hours without calling Google' do
      expect(call(start: '2030-01-15T07:00:00-05:00')).to include('fuera de los días u horas del calendario')
      expect(client).not_to have_received(:create_event)
    end

    it 'rejects a closed day' do
      calendar.update!(working_days: [1])

      expect(call).to include('fuera de los días u horas del calendario')
    end

    it 'rejects a time beyond the booking window' do
      expect(call(start: '2030-03-01T10:00:00-05:00')).to include('fuera del plazo', '14 días')
    end

    it 'rejects a time inside the minimum notice' do
      expect(call(start: '2030-01-14T12:30:00-05:00')).to include('fuera del plazo')
    end

    it 'rejects a start it cannot read' do
      expect(call(start: '2030-13-45T10:00:00-05:00')).to include('No se pudo leer ese horario')
    end

    it 'asks the customer to choose again for a reply that is not an option (anymore)' do
      expect(call(start: 'pasado mañana')).to include('venció', 'check_availability')
      expect(call(start: 'mar 15/01 · 10:00')).to include('venció')
      expect(client).not_to have_received(:create_event)
    end

    it 'relays a calendar failure as a short message and books nothing' do
      allow(client).to receive(:create_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('boom', code: 503))

      result = call

      expect(result).to include('No se pudo acceder al calendario')
      expect(result).not_to include('boom')
      expect(CalendarEvent.count).to eq(0)
    end
  end

  it 'books once when the same call is retried' do
    first = call
    second = call

    expect(second).to eq(first)
    expect(client).to have_received(:create_event).once
    expect(CalendarEvent.count).to eq(1)
  end

  it 'treats another time in the same conversation as another booking' do
    call
    call(start: '2030-01-15T11:00:00-05:00')

    expect(client).to have_received(:create_event).twice
  end
end

RSpec.describe Captain::Tools::AppointmentListTool do
  include_context 'with an appointments conversation'

  def call
    tool.perform(tool_context)
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'lists only this customer upcoming appointments with their ids' do
    local_event(google_event_id: 'own-1', summary: 'Cita con Ana Pérez', contact: contact)
    local_event(google_event_id: 'other-1', contact: create(:contact, account: account),
                start_at: Time.zone.parse('2030-01-16T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-16T10:30:00-05:00'))
    local_event(google_event_id: 'past-1', contact: contact,
                start_at: Time.zone.parse('2030-01-10T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-10T10:30:00-05:00'))
    local_event(google_event_id: 'gone-1', contact: contact, deleted_at: Time.current,
                start_at: Time.zone.parse('2030-01-17T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-17T10:30:00-05:00'))

    result = call

    expect(result).to include('Citas próximas del cliente', '- martes 15/01 10:00 | Cita con Ana Pérez | id=own-1')
    expect(result).not_to include('other-1', 'past-1', 'gone-1')
  end

  it 'says so when there are none' do
    expect(call).to eq('El cliente no tiene citas próximas.')
  end
end

RSpec.describe Captain::Tools::RescheduleAppointmentTool do
  include_context 'with an appointments conversation'

  let!(:own_event) { local_event(google_event_id: 'own-1', summary: 'Cita con Ana Pérez', contact: contact) }
  let(:new_start) { '2030-01-16T15:00:00-05:00' }

  def call(**params)
    tool.perform(tool_context, **{ event_id: 'own-1', new_start: new_start, customer_confirmed: true }.merge(params))
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'moves the customer appointment keeping its length and title' do
    expect(call).to eq('Reprogramada: miércoles 16/01 15:00.')

    expect(own_event.reload).to have_attributes(start_at: Time.zone.parse(new_start), end_at: Time.zone.parse('2030-01-16T15:30:00-05:00'))
    expect(client).to have_received(:update_event).with(hash_including(event_id: 'own-1', summary: 'Cita con Ana Pérez'))
  end

  it 'needs the explicit confirmation' do
    expect(call(customer_confirmed: false)).to include('customer_confirmed true')
    expect(client).not_to have_received(:update_event)
  end

  it 'only touches the appointments of this customer' do
    local_event(google_event_id: 'other-1', contact: create(:contact, account: account))

    expect(call(event_id: 'other-1')).to include('No se encontró esa cita')
    expect(call(event_id: 'unknown')).to include('No se encontró esa cita')
    expect(client).not_to have_received(:update_event)
  end

  it 'will not move it outside the calendar hours' do
    expect(call(new_start: '2030-01-16T22:00:00-05:00')).to include('fuera de los días u horas del calendario')
    expect(client).not_to have_received(:update_event)
  end

  it 'will not move it to a taken time' do
    local_event(contact: nil, start_at: Time.zone.parse('2030-01-16T15:00:00-05:00'), end_at: Time.zone.parse('2030-01-16T15:30:00-05:00'))

    expect(call).to include('ya no está disponible')
  end

  it 'will not move it past the booking window' do
    expect(call(new_start: '2030-03-01T10:00:00-05:00')).to include('fuera del plazo')
  end

  it 'relays a calendar failure as a short message' do
    allow(client).to receive(:update_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('boom', code: 500))

    expect(call).to include('No se pudo acceder al calendario')
  end
end

RSpec.describe Captain::Tools::CancelAppointmentTool do
  include_context 'with an appointments conversation'

  let!(:own_event) { local_event(google_event_id: 'own-1', summary: 'Cita con Ana Pérez', contact: contact) }

  def call(**params)
    tool.perform(tool_context, **{ event_id: 'own-1', customer_confirmed: true }.merge(params))
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'cancels the customer appointment and records who and why' do
    expect(call).to eq('Cancelada: martes 15/01 10:00.')

    expect(own_event.reload.deleted_at).to be_present
    expect(own_event.activities.find_by(action: 'deleted').details).to include('note' => 'Cancelada por el cliente vía Asistente de Ventas')
    expect(client).to have_received(:delete_event).with(hash_including(calendar_id: 'cal-1', event_id: 'own-1'))
  end

  it 'needs the explicit confirmation' do
    expect(call(customer_confirmed: nil)).to include('customer_confirmed true')
    expect(own_event.reload.deleted_at).to be_nil
  end

  it 'only cancels the appointments of this customer' do
    other = local_event(google_event_id: 'other-1', contact: create(:contact, account: account))

    expect(call(event_id: 'other-1')).to include('No se encontró esa cita')
    expect(other.reload.deleted_at).to be_nil
    expect(client).not_to have_received(:delete_event)
  end

  it 'writes the note in the account language' do
    account.update!(locale: 'en')

    call

    expect(own_event.activities.find_by(action: 'deleted').details['note']).to eq('Cancelled by the customer via Asistente de Ventas')
  end
end

RSpec.describe Captain::Tools::ProposeAppointmentTool do
  include_context 'with an appointments conversation'

  let(:start) { '2030-01-15T10:00:00-05:00' }

  def call(**params)
    tool.perform(tool_context, **{ start: start }.merge(params))
  end

  it_behaves_like 'an appointment tool that needs the channel enabled'

  it 'attaches yes / another time buttons and tells the model what to ask' do
    result = call

    expect(result).to include('¿Te reservo martes 15/01 10:00?', '"Sí, reservar ·', 'book_appointment')
    expect(Captain::QuickReplies.take(conversation)).to eq(
      [{ 'title' => 'Sí, reservar', 'value' => 'Sí, reservar · mar 15/01 10:00' },
       { 'title' => 'Otra hora', 'value' => 'Otra hora' }]
    )
  end

  it 'remembers which start the readable yes stands for, with an id up to 256 characters' do
    call

    expect(Captain::QuickReplies.choice(conversation, 'Sí, reservar · mar 15/01 10:00')).to eq('start' => '2030-01-15T10:00:00-05:00')
    expect('Sí, reservar · mar 15/01 10:00'.length).to be <= 256
  end

  it 'accepts the readable text of a time button the customer tapped' do
    Captain::Tools::CheckAvailabilityTool.new(assistant).perform(tool_context, from_date: '2030-01-15', to_date: '2030-01-15')

    result = call(start: 'mar 15/01 · 14:00')

    expect(result).to include('¿Te reservo martes 15/01 14:00?')
    expect(Captain::QuickReplies.choice(conversation, 'Sí, reservar · mar 15/01 14:00')).to eq('start' => '2030-01-15T14:00:00-05:00')
  end

  it 'asks to choose again when the tapped option is unknown or expired' do
    expect(call(start: 'mar 15/01 · 14:00')).to include('venció')
    expect(Captain::QuickReplies.take(conversation)).to be_nil
  end

  it 'books nothing by itself' do
    call

    expect(client).not_to have_received(:create_event)
    expect(CalendarEvent.count).to eq(0)
  end

  it 'proposes moving an existing appointment with its own confirmation button' do
    local_event(google_event_id: 'own-1', contact: contact)

    result = call(start: '2030-01-16T15:00:00-05:00', event_id: 'own-1')

    expect(result).to include('¿Muevo tu cita a miércoles 16/01 15:00?', '"Sí, cambiarla ·', 'reschedule_appointment')
    expect(Captain::QuickReplies.take(conversation)).to eq(
      [{ 'title' => 'Sí, cambiarla', 'value' => 'Sí, cambiarla · mié 16/01 15:00' },
       { 'title' => 'Otra hora', 'value' => 'Otra hora' }]
    )
    expect(Captain::QuickReplies.choice(conversation, 'Sí, cambiarla · mié 16/01 15:00')).to eq(
      'start' => '2030-01-16T15:00:00-05:00', 'event_id' => 'own-1'
    )
  end

  it 'takes the appointment from the "Cambiar hora" reply when no id is passed' do
    local_event(google_event_id: 'own-1', contact: contact)
    Captain::Tools::AppointmentListTool.new(assistant).perform(tool_context, offer_changes: true)

    result = call(start: '2030-01-16T15:00:00-05:00', event_id: 'Cambiar hora')

    expect(result).to include('¿Muevo tu cita a')
    expect(Captain::QuickReplies.choice(conversation, 'Sí, cambiarla · mié 16/01 15:00')).to include('event_id' => 'own-1')
  end

  it 'only proposes moving the appointments of this customer' do
    local_event(google_event_id: 'other-1', contact: create(:contact, account: account))

    expect(call(event_id: 'other-1')).to include('No se encontró esa cita')
    expect(Captain::QuickReplies.take(conversation)).to be_nil
  end

  it 'keeps the button titles within the WhatsApp limit in both languages' do
    call
    spanish = Captain::QuickReplies.take(conversation).pluck('title')
    account.update!(locale: 'en')
    call
    english = Captain::QuickReplies.take(conversation).pluck('title')

    expect(english).to eq(['Yes, book it', 'Another time'])
    expect((spanish + english).map(&:length).max).to be <= 20
  end

  it 'does not propose a time that is taken, outside the hours or outside the window' do
    local_event(start_at: Time.zone.parse('2030-01-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:30:00-05:00'))

    expect(call).to include('ya no está disponible')
    expect(call(start: '2030-01-15T07:00:00-05:00')).to include('ya no está disponible')
    expect(call(start: '2030-03-01T10:00:00-05:00')).to include('fuera del plazo')
    expect(call(start: '2030-13-45T10:00:00-05:00')).to include('No se pudo leer ese horario')
    expect(Captain::QuickReplies.take(conversation)).to be_nil
  end

  context 'with a channel that has no buttons' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

    it 'asks in text for a yes and stashes nothing' do
      result = call

      expect(result).to include('¿Te reservo martes 15/01 10:00?', 'responda sí')
      expect(Captain::QuickReplies.take(conversation)).to be_nil
    end
  end
end

RSpec.describe Captain::Tools::AppointmentListTool, 'change buttons' do
  include_context 'with an appointments conversation'

  def call(**params)
    tool.perform(tool_context, **params)
  end

  let!(:own_event) { local_event(google_event_id: 'own-1', summary: 'Cita con Ana Pérez', contact: contact) }

  it 'attaches change / cancel / keep buttons when the customer asked to change something' do
    result = call(offer_changes: true)

    expect(result.lines.last).to include('"Cambiar hora"', '"Cancelar cita"', '"Dejarla así"')
    expect(Captain::QuickReplies.take(conversation)).to eq(
      [{ 'title' => 'Cambiar hora', 'value' => 'Cambiar hora' },
       { 'title' => 'Cancelar cita', 'value' => 'Cancelar cita' },
       { 'title' => 'Dejarla así', 'value' => 'Dejarla así' }]
    )
  end

  it 'remembers the appointment each change button stands for' do
    call(offer_changes: true)

    ['Cambiar hora', 'Cancelar cita', 'Dejarla así'].each do |reply|
      expect(Captain::QuickReplies.choice(conversation, reply)).to eq('event_id' => 'own-1')
    end
  end

  it 'attaches nothing when the customer only asked what they have' do
    call

    expect(Captain::QuickReplies.take(conversation)).to be_nil
  end

  it 'attaches nothing, and asks which one, when the customer has several appointments' do
    local_event(google_event_id: 'other-1', contact: contact,
                start_at: Time.zone.parse('2030-01-16T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-16T10:30:00-05:00'))

    result = call(offer_changes: true)

    expect(result.lines.last).to include('cambiar la hora, cancelar la cita o dejarla así')
    expect(Captain::QuickReplies.take(conversation)).to be_nil
  end

  context 'with a channel that has no buttons' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

    it 'asks in text what they want to do' do
      result = call(offer_changes: true)

      expect(result.lines.last).to include('cambiar la hora, cancelar la cita o dejarla así')
      expect(Captain::QuickReplies.take(conversation)).to be_nil
    end
  end
end

RSpec.describe Captain::Tools::BookAppointmentTool, 'button replies' do
  include_context 'with an appointments conversation'

  def propose(start)
    Captain::Tools::ProposeAppointmentTool.new(assistant).perform(tool_context, start: start)
  end

  it 'books from the readable text of the yes button the customer tapped' do
    propose('2030-01-15T10:00:00-05:00')

    result = tool.perform(tool_context, start: 'Sí, reservar · mar 15/01 10:00', customer_confirmed: true)

    expect(result).to start_with('Agendada: martes 15/01 10:00')
    expect(CalendarEvent.find_by(google_event_id: 'g-1').start_at).to eq(Time.zone.parse('2030-01-15T10:00:00-05:00'))
  end

  it 'still needs customer_confirmed even for the text of the yes button' do
    propose('2030-01-15T10:00:00-05:00')

    expect(tool.perform(tool_context, start: 'Sí, reservar · mar 15/01 10:00', customer_confirmed: false)).to include('customer_confirmed true')
    expect(client).not_to have_received(:create_event)
  end

  it 'books again from the same reply after asking for a missing detail' do
    contact.update!(phone_number: nil)
    propose('2030-01-15T10:00:00-05:00')
    reply = 'Sí, reservar · mar 15/01 10:00'

    expect(tool.perform(tool_context, start: reply, customer_confirmed: true)).to include('teléfono')
    expect(tool.perform(tool_context, start: reply, customer_confirmed: true, phone: '+593991234567')).to start_with('Agendada')
  end

  it 'asks the customer to choose again when the choices expired' do
    result = tool.perform(tool_context, start: 'Sí, reservar · mar 15/01 10:00', customer_confirmed: true)

    expect(result).to include('venció', 'check_availability')
    expect(client).not_to have_received(:create_event)
  end

  it 'books from the readable text of a time button too' do
    Captain::Tools::CheckAvailabilityTool.new(assistant).perform(tool_context, from_date: '2030-01-15', to_date: '2030-01-15')

    result = tool.perform(tool_context, start: 'mar 15/01 · 14:00', customer_confirmed: true)

    expect(result).to start_with('Agendada: martes 15/01 14:00')
  end

  it 'still accepts the exact ISO start' do
    expect(tool.perform(tool_context, start: '2030-01-15T10:00:00-05:00', customer_confirmed: true)).to start_with('Agendada')
  end
end

RSpec.describe Captain::Tools::RescheduleAppointmentTool, 'button replies' do
  include_context 'with an appointments conversation'

  let!(:own) { local_event(google_event_id: 'own-1', contact: contact) }

  def propose_move
    Captain::Tools::ProposeAppointmentTool.new(assistant).perform(tool_context, start: '2030-01-16T15:00:00-05:00', event_id: 'own-1')
  end

  it 'moves the appointment from the yes button text alone, which carries the appointment too' do
    propose_move

    result = tool.perform(tool_context, new_start: 'Sí, cambiarla · mié 16/01 15:00', customer_confirmed: true)

    expect(result).to eq('Reprogramada: miércoles 16/01 15:00.')
    expect(own.reload.start_at).to eq(Time.zone.parse('2030-01-16T15:00:00-05:00'))
  end

  it 'still needs customer_confirmed' do
    propose_move

    expect(tool.perform(tool_context, new_start: 'Sí, cambiarla · mié 16/01 15:00')).to include('customer_confirmed true')
    expect(client).not_to have_received(:update_event)
  end

  it 'asks the customer to choose again when the choices expired' do
    expect(tool.perform(tool_context, new_start: 'Sí, cambiarla · mié 16/01 15:00', customer_confirmed: true)).to include('venció')
  end

  it 'still accepts the id and the ISO start' do
    result = tool.perform(tool_context, event_id: 'own-1', new_start: '2030-01-16T15:00:00-05:00', customer_confirmed: true)

    expect(result).to start_with('Reprogramada')
  end
end

RSpec.describe Captain::Tools::CancelAppointmentTool, 'button replies' do
  include_context 'with an appointments conversation'

  let!(:own) { local_event(google_event_id: 'own-1', contact: contact) }

  it 'cancels the appointment named by the "Cancelar cita" reply' do
    Captain::Tools::AppointmentListTool.new(assistant).perform(tool_context, offer_changes: true)

    result = tool.perform(tool_context, event_id: 'Cancelar cita', customer_confirmed: true)

    expect(result).to eq('Cancelada: martes 15/01 10:00.')
    expect(own.reload.deleted_at).to be_present
  end

  it 'finds nothing when the reply is not a known button any more' do
    expect(tool.perform(tool_context, event_id: 'Cancelar cita', customer_confirmed: true)).to include('No se encontró esa cita')
    expect(own.reload.deleted_at).to be_nil
  end
end

RSpec.describe Captain::Assistant, 'appointment tools exposure' do
  include_context 'with an appointments conversation'

  let(:runner) { Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conversation) }
  let(:instructions_context) do
    Struct.new(:context).new({ state: { conversation: { id: conversation.id, inbox_id: inbox.id }, assistant_config: {}, timezone: 'UTC' } })
  end

  it 'builds the six appointment tools' do
    expect(assistant.appointment_tools.map(&:class)).to eq(
      [Captain::Tools::CheckAvailabilityTool, Captain::Tools::ProposeAppointmentTool, Captain::Tools::BookAppointmentTool,
       Captain::Tools::AppointmentListTool, Captain::Tools::RescheduleAppointmentTool, Captain::Tools::CancelAppointmentTool]
    )
  end

  it 'registers them in the built-in tools list' do
    expect(Captain::Assistant.built_in_tool_ids).to include(*Captain::Assistant::APPOINTMENT_TOOL_IDS)
  end

  it 'gives the assistant the tools only in an inbox where appointments are active' do
    agent = assistant.agent
    with_tools = runner.send(:with_appointment_tools, agent)

    expect(with_tools.tools.map(&:class)).to include(*assistant.appointment_tools.map(&:class))
    expect(agent.tools.map(&:class)).not_to include(Captain::Tools::BookAppointmentTool)
  end

  it 'keeps the tools away when the channel switched appointments off' do
    captain_inbox.update!(appointments_enabled: false)

    expect(runner.send(:with_appointment_tools, assistant.agent).tools.map(&:class)).not_to include(Captain::Tools::BookAppointmentTool)
  end

  it 'keeps the tools away when the assistant has appointments off' do
    assistant.update!(config: assistant.config.merge('appointments' => appointments_config.merge('enabled' => false)))

    expect(runner.send(:with_appointment_tools, assistant.agent).tools.map(&:class)).not_to include(Captain::Tools::BookAppointmentTool)
  end

  it 'adds the confirm-before-booking rules to the prompt only when appointments are active' do
    prompt = assistant.agent_instructions(instructions_context)

    expect(prompt).to include('# Appointments', 'captain--tools--book_appointment', 'explicit yes', 'customer_confirmed')
    expect(prompt).to include('captain--tools--propose_appointment', 'UNCHANGED', 'Sí, reservar · jue 16/01 10:00', 'expired')
    expect(prompt).to include('30 minutes', 'name, phone, email')

    captain_inbox.update!(appointments_enabled: false)
    expect(assistant.agent_instructions(instructions_context)).not_to include('# Appointments')
  end
end
