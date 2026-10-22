require 'rails_helper'

describe Whatsapp::IncomingMessageWhatsappCloudService, '#perform' do
  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  let(:account) { create(:account, locale: 'es') }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:sender_number) { '2423423243' }
  let(:contact) { create(:contact, account: account, phone_number: "+#{sender_number}") }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: sender_number) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:appointment) do
    CalendarEvent.create!(
      account: account, calendar_connection: connection, external_calendar_id: 'cal-1', google_event_id: 'g-1', summary: 'Consulta',
      start_at: 2.days.from_now, end_at: 2.days.from_now + 30.minutes, conversation: conversation, contact: contact,
      appointment_status: 'pending_confirmation'
    )
  end

  before do
    conversation.messages.create!(
      account: account, inbox: channel.inbox, message_type: :outgoing, content: 'Hola', source_id: 'wamid.NOTICE',
      additional_attributes: { 'template_params' => { 'name' => 'cita_confirmacion' }, 'calendar_event_id' => appointment.id }
    )
  end

  def params_for(message)
    {
      phone_number: channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: { contacts: [{ profile: { name: 'Ana Pérez' }, wa_id: sender_number }],
                                     messages: [{ from: sender_number, id: 'wamid.ANSWER', timestamp: '1664799904' }.merge(message)] } }] }]
    }.with_indifferent_access
  end

  it 'confirms the appointment when the customer taps the button of the template' do
    button = { type: 'button', button: { payload: 'Confirmar', text: 'Confirmar' }, context: { from: channel.phone_number, id: 'wamid.NOTICE' } }

    described_class.new(inbox: channel.inbox, params: params_for(button)).perform

    expect(appointment.reload.appointment_status).to eq('confirmed')
    expect(conversation.messages.incoming.last.content).to eq('Confirmar')
  end

  it 'does not change the appointment when the customer types the same word' do
    described_class.new(inbox: channel.inbox, params: params_for(type: 'text', text: { body: 'Confirmar' })).perform

    expect(appointment.reload.appointment_status).to eq('pending_confirmation')
  end

  it 'still saves the message when answering the appointment fails' do
    allow(Calendar::TemplateButtonReply).to receive(:new).and_raise(StandardError)
    button = { type: 'button', button: { payload: 'Cancelar', text: 'Cancelar' }, context: { id: 'wamid.NOTICE' } }

    described_class.new(inbox: channel.inbox, params: params_for(button)).perform

    expect(conversation.messages.incoming.last.content).to eq('Cancelar')
    expect(appointment.reload.appointment_status).to eq('pending_confirmation')
  end
end
