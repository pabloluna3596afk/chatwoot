require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService, '#destroy cancellation notice' do
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
  let(:client) { instance_double(Integrations::GoogleCalendar::Client, delete_event: {}) }
  let(:service) { described_class.new(account: account, user: user, connection: connection) }
  let(:params) { { calendar_id: 'cal-1', note: 'Private internal note', send_to_contact: true } }

  before do
    appointment
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
  end

  after do
    Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: 'g-1'))
  end

  it 'sends cancellation once, without the internal note or free text' do
    2.times { service.destroy('g-1', params) }

    expect(outgoing.count).to eq(1)
    expect(outgoing.last.additional_attributes['template_params']['name']).to eq('cita_cancelacion')
    expect(outgoing.last.content).not_to include(params[:note])
    expect(appointment.reload).to be_discarded
  end

  it 'does not send when Captain cancels' do
    bot = create(:agent_bot, account: account)

    described_class.new(account: account, user: bot, connection: connection).destroy('g-1', params)

    expect(outgoing).to be_empty
    expect(appointment.reload).to be_discarded
  end

  it 'does not send when the customer cancels through the template button with user nil' do
    described_class.new(account: account, user: nil, connection: connection).cancel_by_customer!(appointment)

    expect(outgoing).to be_empty
    expect(appointment.reload).to be_discarded
  end

  it 'does not send when Google cancels the event' do
    allow(client).to receive(:list_events).and_return([{ 'id' => 'g-1', 'status' => 'cancelled' }])

    service.list(calendar_id: 'cal-1', time_min: '2030-01-01T00:00:00Z', time_max: '2030-02-01T00:00:00Z')

    expect(outgoing).to be_empty
    expect(appointment.reload).to be_discarded
  end

  it 'does not send for a past appointment' do
    appointment.update!(start_at: 1.day.ago, end_at: 1.day.ago + 30.minutes)

    service.destroy('g-1', params)

    expect(outgoing).to be_empty
  end

  it 'does not send without a conversation' do
    appointment.update!(conversation: nil)

    expect { service.destroy('g-1', params) }.not_to change(Message, :count)
  end

  it 'does not send on a channel other than WhatsApp Cloud' do
    channel.update!(provider: 'default')

    service.destroy('g-1', params)

    expect(outgoing).to be_empty
  end

  context 'with a conversation on another channel' do
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    it 'cancels without sending a customer message' do
      service.destroy('g-1', params)

      expect(outgoing).to be_empty
      expect(appointment.reload).to be_discarded
    end
  end

  it 'does not send when Panel AI follow-up is active' do
    appointment.update!(bot_followup_policy: { enabled: true })

    service.destroy('g-1', params)

    expect(outgoing).to be_empty
  end

  it 'does not send when already cancelled without a deletion timestamp' do
    appointment.update!(appointment_status: 'cancelled')

    service.destroy('g-1', params)

    expect(outgoing).to be_empty
  end

  it 'does not send when already soft deleted' do
    appointment.update!(deleted_at: Time.current, appointment_status: 'cancelled')

    service.destroy('g-1', params)

    expect(outgoing).to be_empty
  end

  context 'without an approved cancellation template' do
    let(:templates) { [] }

    it 'leaves a cancellation activity and never sends free text' do
      I18n.with_locale(:es) { service.destroy('g-1', params) }

      expect(outgoing).to be_empty
      expect(Conversations::ActivityMessageJob).to have_been_enqueued.with(
        conversation, hash_including(content: a_string_including('falta la plantilla de cancelación aprobada'))
      )
      expect(appointment.reload).to be_discarded
    end
  end

  it 'keeps the cancellation when delivery fails and logs no sensitive data' do
    notice = instance_double(Integrations::GoogleCalendar::CustomerNotice, whatsapp_cloud?: true)
    allow(Integrations::GoogleCalendar::CustomerNotice).to receive(:new).and_return(notice)
    allow(notice).to receive(:deliver!).and_raise(StandardError, 'sensitive Meta response')
    allow(Rails.logger).to receive(:error)

    expect(service.destroy('g-1', params)).to include(deleted: true)
    expect(appointment.reload).to be_discarded
    expect(Rails.logger).to have_received(:error).with('Calendar WhatsApp cancellation notice failed: StandardError')
  end
end
