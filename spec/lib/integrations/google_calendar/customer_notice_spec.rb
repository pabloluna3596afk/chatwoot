require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::CustomerNotice do
  let(:account) { create(:account, locale: 'es') }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let(:templates) do
    [{ 'name' => 'cita_cancelacion', 'language' => account.locale, 'status' => 'APPROVED', 'category' => 'UTILITY' }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact) }
  let(:appointment) do
    CalendarEvent.create!(
      account: account, calendar_connection: connection, external_calendar_id: 'cal-1', google_event_id: 'g-1',
      summary: 'Consulta', start_at: Time.zone.parse('2030-01-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:30:00-05:00'),
      conversation: conversation, contact: contact, created_by: user
    )
  end
  let(:outgoing) { conversation.messages.outgoing }
  let(:notice) do
    described_class.new(conversation: conversation, record: appointment, timezone: 'America/Guayaquil', sender: user,
                        template_name: Calendar::ActivationKit::CANCEL_TEMPLATE_NAME)
  end

  it 'sends resolved cancellation values and keeps the appointment identifier' do
    expect(notice.deliver!).to be(true)

    message = outgoing.last
    expect(message.additional_attributes).to include('calendar_event_id' => appointment.id)
    expect(message.additional_attributes['template_params']).to include(
      'name' => 'cita_cancelacion', 'language' => 'es', 'content_mode' => 'rendered',
      'processed_params' => { 'body' => { 'nombre' => 'Ana Pérez', 'cita' => 'Consulta', 'fecha' => '15/01/2030', 'hora' => '10:00' } }
    )
    expect(message.content).to include('fue cancelada')
    expect(message.sender).to eq(user)
  end

  it 'uses the English body and date format' do
    account.update!(locale: 'en')

    notice.deliver!

    expect(outgoing.last.content).to include('was cancelled', '01/15/2030', '10:00')
    expect(outgoing.last.additional_attributes['template_params']['language']).to eq('en')
  end

  it 'does not render contact or appointment text as Liquid' do
    contact.update!(name: '{{ account.name }}')
    appointment.update!(summary: '{{ contact.name }}')

    notice.deliver!

    expect(outgoing.last.content).to include('{{ account.name }}', '{{ contact.name }}')
  end

  it 'does not use an approved confirmation template as a cancellation notice' do
    channel.update!(message_templates: templates.map { |template| template.merge('name' => 'cita_confirmacion') })

    expect(notice.deliver!).to be(false)
    expect(outgoing).to be_empty
  end

  %w[PENDING REJECTED].each do |state|
    it "does not send a #{state} cancellation template" do
      channel.update!(message_templates: templates.map { |template| template.merge('status' => state) })

      expect(notice.deliver!).to be(false)
      expect(outgoing).to be_empty
    end
  end
end
