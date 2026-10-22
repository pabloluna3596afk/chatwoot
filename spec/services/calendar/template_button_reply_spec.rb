require 'rails_helper'

RSpec.shared_examples 'calendar template button replies' do |template_name|
  let(:account) { create(:account, locale: 'es') }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact) }
  let(:client) { instance_double(Integrations::GoogleCalendar::Client, delete_event: nil) }
  let(:start_at) { 2.days.from_now.change(usec: 0) }
  let(:appointment) { create_appointment('Consulta', start_at) }
  let!(:notice) { template_message(appointment, name: template_name) }

  def create_appointment(summary, start, status: 'pending_confirmation')
    CalendarEvent.create!(
      account: account, calendar_connection: connection, external_calendar_id: 'cal-1', google_event_id: "g-#{SecureRandom.hex(4)}",
      summary: summary, start_at: start, end_at: start + 30.minutes, conversation: conversation, contact: contact,
      created_by: user, appointment_status: status
    )
  end

  def template_message(event, name: Calendar::ActivationKit::TEMPLATE_NAME)
    conversation.messages.create!(
      account: account, inbox: channel.inbox, message_type: :outgoing, content: 'Hola', source_id: "wamid-#{SecureRandom.hex(3)}",
      additional_attributes: { 'template_params' => { 'name' => name }, 'calendar_event_id' => event.id }
    )
  end

  def tap_button(label, reply_to: notice)
    attrs = reply_to ? { 'in_reply_to' => reply_to.id } : {}
    conversation.messages.create!(
      account: account, inbox: channel.inbox, message_type: :incoming, content: label, sender: contact, content_attributes: attrs
    )
  end

  def activity_texts
    conversation.messages.activity.order(:id).pluck(:content)
  end

  before do
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
  end

  describe 'Confirmar' do
    it 'confirms the appointment, keeps the history and tells the team' do
      described_class.new(tap_button('Confirmar')).perform

      expect(appointment.reload.appointment_status).to eq('confirmed')
      activity = appointment.activities.last
      expect(activity).to have_attributes(action: 'updated', user: nil)
      expect(activity.details).to include('appointment_status' => %w[pending_confirmation confirmed], 'source' => 'customer')
      expect(activity_texts.last).to eq('Ana Pérez confirmó la cita "Consulta" con el botón de la plantilla')
    end

    it 'understands the English label in an English account' do
      account.update!(locale: 'en')

      described_class.new(tap_button('Confirm')).perform

      expect(appointment.reload.appointment_status).to eq('confirmed')
      expect(activity_texts.last).to eq('Ana Pérez confirmed the appointment "Consulta" with the template button')
    end

    it 'does nothing new when the customer taps it twice' do
      2.times { described_class.new(tap_button('Confirmar')).perform }

      expect(appointment.activities.count).to eq(1)
      expect(activity_texts.size).to eq(1)
    end
  end

  describe 'Cancelar' do
    it 'cancels the appointment in Google and locally, and tells the team' do
      described_class.new(tap_button('Cancelar')).perform

      expect(client).to have_received(:delete_event).with(calendar_id: 'cal-1', event_id: appointment.google_event_id, etag: nil)
      expect(appointment.reload).to have_attributes(appointment_status: 'cancelled', idempotency_key: nil)
      expect(appointment.deleted_at).to be_present
      expect(appointment.activities.last).to have_attributes(action: 'deleted', user: nil)
      expect(activity_texts.last).to eq('Ana Pérez canceló la cita "Consulta" con el botón de la plantilla')
    end

    it 'understands the English label' do
      account.update!(locale: 'en')

      described_class.new(tap_button('Cancel')).perform

      expect(appointment.reload.appointment_status).to eq('cancelled')
    end

    it 'treats an event already gone from Google as cancelled' do
      allow(client).to receive(:delete_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('gone', code: 404))

      described_class.new(tap_button('Cancelar')).perform

      expect(appointment.reload.appointment_status).to eq('cancelled')
    end

    it 'leaves the appointment untouched, and the answer open, when Google fails' do
      allow(client).to receive(:delete_event).and_raise(Integrations::GoogleCalendar::Client::Error.new('boom', code: 500))

      described_class.new(tap_button('Cancelar')).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts.last).to include('no se pudo cancelar en Google')
      expect(notice.reload.additional_attributes).not_to have_key('customer_answer')
    end
  end

  describe 'Reagendar' do
    it 'does not touch the appointment and asks the team for a new time once' do
      2.times { described_class.new(tap_button('Reagendar')).perform }

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts).to eq(['Ana Pérez pidió reagendar la cita "Consulta". Propón una nueva hora'])
    end

    it 'understands the English label' do
      account.update!(locale: 'en')

      described_class.new(tap_button('Reschedule')).perform

      expect(activity_texts.last).to include('asked to reschedule')
    end
  end

  describe 'appointments that no longer apply' do
    it 'does not change an appointment that already took place and says so' do
      appointment.update!(start_at: 1.day.ago, end_at: 1.day.ago + 30.minutes)

      described_class.new(tap_button('Confirmar')).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts.last).to include('la cita ya pasó y no se cambió')
    end

    it 'does not change a cancelled appointment and says so' do
      appointment.update!(appointment_status: 'cancelled', deleted_at: Time.current)

      described_class.new(tap_button('Confirmar')).perform

      expect(appointment.reload.appointment_status).to eq('cancelled')
      expect(activity_texts.last).to include('ya estaba cancelada')
    end
  end

  describe 'which appointment' do
    let(:later_appointment) { create_appointment('Control', start_at + 1.day) }

    before { template_message(later_appointment, name: template_name) }

    it 'answers the appointment of the message the button belongs to' do
      described_class.new(tap_button('Confirmar', reply_to: notice)).perform

      expect(appointment.reload.appointment_status).to eq('confirmed')
      expect(later_appointment.reload.appointment_status).to eq('pending_confirmation')
    end

    it 'answers the latest template sent when Meta gives no context' do
      described_class.new(tap_button('Confirmar', reply_to: nil)).perform

      expect(later_appointment.reload.appointment_status).to eq('confirmed')
      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
    end

    it 'selects the latest reminder without context and ignores a newer cancellation notice' do
      template_message(later_appointment, name: 'cita_recordatorio')
      template_message(appointment, name: 'cita_cancelacion')
      described_class.new(tap_button('Confirmar', reply_to: nil)).perform
      expect(later_appointment.reload.appointment_status).to eq('confirmed')
      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
    end

    it 'ignores a button replying to a message that is not our template' do
      other = template_message(appointment, name: 'otra_plantilla')

      described_class.new(tap_button('Confirmar', reply_to: other)).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts).to be_empty
    end

    it 'ignores cancellation notices because they have no quick reply buttons' do
      cancellation = template_message(appointment, name: Calendar::ActivationKit::CANCEL_TEMPLATE_NAME)
      described_class.new(tap_button('Confirmar', reply_to: cancellation)).perform
      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts).to be_empty
    end

    it 'ignores a button replying to a regular message' do
      regular = conversation.messages.create!(account: account, inbox: channel.inbox, message_type: :outgoing, content: 'Hola')

      described_class.new(tap_button('Confirmar', reply_to: regular)).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
    end

    it 'does not act on the appointment of another conversation' do
      other_conversation = create(:conversation, account: account, inbox: channel.inbox, contact: create(:contact, account: account))
      foreign = template_message(appointment)
      foreign.update_columns(conversation_id: other_conversation.id) # rubocop:disable Rails/SkipsModelValidations
      reply = other_conversation.messages.create!(
        account: account, inbox: channel.inbox, message_type: :incoming, content: 'Confirmar',
        content_attributes: { 'in_reply_to' => foreign.id }
      )

      described_class.new(reply).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
    end
  end

  describe 'buttons that are not an answer' do
    it 'ignores other texts' do
      described_class.new(tap_button('Gracias')).perform

      expect(appointment.reload.appointment_status).to eq('pending_confirmation')
      expect(activity_texts).to be_empty
    end
  end

  describe 'failures' do
    it 'never raises into the processing of the incoming message' do
      allow(CalendarEvent).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid)

      expect { described_class.new(tap_button('Confirmar')).perform }.not_to raise_error
    end
  end
end

RSpec.describe Calendar::TemplateButtonReply do
  %w[cita_confirmacion cita_recordatorio].each do |template_name|
    context "with #{template_name}" do
      it_behaves_like 'calendar template button replies', template_name
    end
  end
end
