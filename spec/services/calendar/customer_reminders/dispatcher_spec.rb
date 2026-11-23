require 'rails_helper'

RSpec.describe Calendar::CustomerReminders::Dispatcher do
  let(:now) { Time.utc(2030, 1, 14, 15) }
  let(:account) { create(:account, locale: 'es', reporting_timezone: 'America/Guayaquil', customer_reminders_enabled: true) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, provider_config: { 'business_account_id' => 'waba-1' }, message_templates: templates)
  end
  let(:templates) do
    [{ 'name' => 'cita_recordatorio', 'language' => account.locale, 'status' => 'APPROVED', 'category' => 'UTILITY' }]
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:event) do
    create(:calendar_event, account: account, calendar_connection: create(:calendar_connection, account: account),
                            conversation: conversation, start_at: now + 24.hours, created_at: now - 2.days)
  end
  let(:outgoing) { conversation.messages.outgoing.reorder(:id) }

  before do
    travel_to(now)
    allow(Automations::ProactiveSendCap).to receive(:new).and_call_original
    event
  end

  it 'R1 claims one reminder across repeated cron runs, using the existing template pipeline' do
    2.times { described_class.new.perform }

    expect(outgoing.count).to eq(1)
    expect(outgoing.last.additional_attributes).to include(
      'calendar_event_id' => event.id,
      'customer_reminder' => { 'start_at' => event.start_at.iso8601(6), 'attempt' => 1 }
    )
    expect(outgoing.last.additional_attributes.dig('template_params', 'name')).to eq('cita_recordatorio')
    expect(event.reload).to have_attributes(customer_reminder_status: 'queued_1', customer_reminder_sent_at: nil)
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'A2 pauses disconnected appointments and resumes once without consuming an attempt' do
    event.calendar_connection.update!(is_active: false)

    2.times { described_class.new.perform }

    expect(outgoing).to be_empty
    expect(event.reload).to have_attributes(customer_reminder_status: nil, customer_reminder_sent_at: nil)
    event.calendar_connection.update!(is_active: true)
    2.times { described_class.new.perform }
    expect(outgoing.count).to eq(1)
    expect(event.reload.customer_reminder_status).to eq('queued_1')
  end

  it 'A2 never requeues an accepted reminder after disconnecting and reconnecting' do
    event.update!(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
    event.calendar_connection.update!(is_active: false)
    described_class.new.perform
    event.calendar_connection.update!(is_active: true)
    described_class.new.perform

    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_sent_at).to eq(now)
  end

  it 'R2 leaves Captain bookings alone' do
    event.update!(booking_source: 'ai')
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'queues the linked reminder version and preserves its resource snapshot' do
    template = {
      'id' => 'reminder-v2', 'name' => 'recordatorio_v2', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => '{{nombre}}, {{cita}}, {{fecha}}, {{hora}}' },
        { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } } }
      ]
    }
    channel.update!(message_templates: [template])
    resources = Calendar::TemplateResources.new(account: account, function: :reminder, language: 'es', channel: channel)
    resource = resources.link!(template_name: template['name'], remote_template_id: template['id'])
    described_class.new.perform
    expect(outgoing.count).to eq(1)
    expect(outgoing.last.additional_attributes.dig('template_params', 'name')).to eq('recordatorio_v2')
    expect(outgoing.last.content_attributes.dig('calendar_template_resource', 'resource_id')).to eq(resource.id)
  end

  it 'does not queue a reclassified legacy reminder or consume an attempt' do
    channel.update!(message_templates: [templates.first.merge('category' => 'MARKETING')])
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to eq('no_template')
    expect(conversation.messages.activity.last.additional_attributes['calendar_template_settings']).to include(
      'path' => "/app/accounts/#{account.id}/settings/templates"
    )
  end

  it 'does not enqueue reminders for appointments that opted out of customer notice' do
    event.update!(customer_reminder_status: 'skipped_opt_out')

    described_class.new.perform

    expect(outgoing).to be_empty
  end

  it 'R3 leaves Panel AI follow-up alone' do
    event.update!(bot_followup_policy: { 'enabled' => true })
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'R4 marks unsupported channels without sending free text' do
    conversation.update!(inbox: create(:inbox, account: account))
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_channel')
    expect(outgoing).to be_empty
  end

  [nil, 'PENDING', 'REJECTED'].each do |state|
    it "R5 retries a #{state || 'missing'} template with only one activity until approval" do
      channel.update!(message_templates: state ? templates.map { |template| template.merge('status' => state) } : [])
      2.times { described_class.new.perform }
      expect(outgoing).to be_empty
      expect(conversation.messages.activity.count).to eq(1)
      message = conversation.messages.activity.last
      expect(message.content_attributes.dig('activity', 'names')).to eq([event.summary])
      expect(message.content).to include(event.summary)
      expect(event.reload.customer_reminder_status).to eq('no_template')
      channel.update!(message_templates: templates)
      described_class.new.perform
      expect(outgoing.count).to eq(1)
    end
  end

  it 'R6 excludes deleted and cancelled appointments' do
    event.update!(deleted_at: now)
    described_class.new.perform
    event.update!(deleted_at: nil, appointment_status: 'cancelled')
    described_class.new.perform
    expect(outgoing).to be_empty
  end

  it 'R7 clears the claim when moved, and reevaluates too-close appointments' do
    described_class.new.perform
    event.reload.update!(start_at: now + 3.days)
    expect(event.reload.customer_reminder_status).to be_nil
    event.update!(start_at: now + 23.hours)
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_too_close')
    expect(outgoing.count).to eq(1)
  end

  it 'R8 excludes appointments created less than 24 hours ahead even before the switch was enabled' do
    account.update!(customer_reminders_enabled: false)
    event.update!(created_at: now - 1.hour, start_at: now + 2.hours)
    expect(event.reload.customer_reminder_status).to be_nil
    account.update!(customer_reminders_enabled: true)
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_too_close')
    expect(outgoing).to be_empty
  end

  it 'R8 also reads the move history if the switch was off during the move' do
    account.update!(customer_reminders_enabled: false)
    event.update!(start_at: now + 2.hours)
    event.activities.create!(account: account, action: 'updated', details: { 'start_at' => ['old', event.start_at.iso8601] })
    account.update!(customer_reminders_enabled: true)
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_too_close')
    expect(outgoing).to be_empty
  end

  it 'R9 never sends after the appointment starts' do
    travel_to(event.start_at)
    described_class.new.perform
    expect(outgoing).to be_empty
  end

  it 'R10 skips already confirmed appointments' do
    event.update!(appointment_status: 'confirmed')
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_confirmed')
    expect(outgoing).to be_empty
  end

  it 'R11 sends an early-morning appointment at 21:00 two calendar dates before it' do
    event.update!(start_at: Time.utc(2030, 1, 16, 12, 59))
    travel_to(Time.utc(2030, 1, 15, 1, 59))
    described_class.new.perform
    expect(outgoing).to be_empty
    travel_to(Time.utc(2030, 1, 15, 2))
    described_class.new.perform
    expect(outgoing.count).to eq(1)
  end

  it 'R11 does not catch up overnight after cron downtime' do
    travel_to(Time.utc(2030, 1, 15, 5))
    described_class.new.perform
    expect(outgoing).to be_empty
    travel_to(Time.utc(2030, 1, 15, 13))
    described_class.new.perform
    expect(outgoing.count).to eq(1)
  end

  it 'R13 sends one message for each appointment of the same customer' do
    other = create(:calendar_event, account: account, calendar_connection: event.calendar_connection,
                                    conversation: conversation, start_at: event.start_at, created_at: event.created_at)
    described_class.new.perform
    expect(outgoing.map { |message| message.additional_attributes['calendar_event_id'] }).to contain_exactly(event.id, other.id)
  end

  it 'R15 enqueues when the contact-date rule cap is exhausted' do
    account.update!(settings: account.settings.merge('proactive_daily_send_cap' => 0))
    described_class.new.perform
    expect(outgoing.count).to eq(1)
    expect(outgoing.last.additional_attributes['customer_reminder']).not_to have_key('cap_date')
  end

  it 'R16 defaults to off and neither sends nor marks anything' do
    account.update!(settings: {})
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to be_nil
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'does not try to deliver appointments without a conversation' do
    event.update!(conversation: nil)
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'isolates a creation failure and stops after three failed attempts' do
    notice = instance_double(Integrations::GoogleCalendar::CustomerNotice, whatsapp_cloud?: true, template: templates.first)
    allow(Integrations::GoogleCalendar::CustomerNotice).to receive(:new).and_return(notice)
    allow(notice).to receive(:deliver!).and_raise(ActiveRecord::RecordInvalid)
    4.times { described_class.new.perform }
    expect(event.reload.customer_reminder_status).to eq('skipped_error')
    expect(outgoing).to be_empty
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end
end
