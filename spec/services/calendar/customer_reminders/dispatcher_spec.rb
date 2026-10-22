require 'rails_helper'

RSpec.describe Calendar::CustomerReminders::Dispatcher do
  let(:now) { Time.utc(2030, 1, 14, 15) }
  let(:account) { create(:account, locale: 'es', reporting_timezone: 'America/Guayaquil', customer_reminders_enabled: true) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates)
  end
  let(:templates) do
    [{ 'name' => 'cita_recordatorio', 'language' => account.locale, 'status' => 'APPROVED', 'category' => 'UTILITY' }]
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:event) do
    create(:calendar_event, account: account, calendar_connection: create(:calendar_connection, account: account),
                            conversation: conversation, start_at: now + 24.hours, created_at: now - 2.days)
  end
  let(:cap) { instance_double(Automations::ProactiveSendCap, reserve!: true, release!: nil) }
  let(:outgoing) { conversation.messages.outgoing.reorder(:id) }

  before do
    travel_to(now)
    allow(Automations::ProactiveSendCap).to receive(:new).and_return(cap)
    event
  end

  it 'R1 claims one reminder across repeated cron runs, using the existing template pipeline' do
    2.times { described_class.new.perform }

    expect(outgoing.count).to eq(1)
    expect(outgoing.last.additional_attributes).to include(
      'calendar_event_id' => event.id,
      'customer_reminder' => { 'start_at' => event.start_at.iso8601(6), 'attempt' => 1, 'cap_date' => now.to_date.iso8601 }
    )
    expect(outgoing.last.additional_attributes.dig('template_params', 'name')).to eq('cita_recordatorio')
    expect(event.reload).to have_attributes(customer_reminder_status: 'queued_1', customer_reminder_sent_at: nil)
    expect(cap).to have_received(:reserve!).once
  end

  it 'R2 leaves Captain bookings alone' do
    event.update!(booking_source: 'ai')
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to be_nil
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

  it 'R15 waits without claiming when the daily cap is exhausted' do
    allow(cap).to receive(:reserve!).and_return(false)
    described_class.new.perform
    expect(event.reload.customer_reminder_status).to be_nil
    expect(outgoing).to be_empty
    allow(cap).to receive(:reserve!).and_return(true)
    described_class.new.perform
    expect(outgoing.count).to eq(1)
  end

  it 'R16 defaults to off and neither sends nor marks anything' do
    account.update!(settings: {})
    described_class.new.perform
    expect(outgoing).to be_empty
    expect(event.reload.customer_reminder_status).to be_nil
    expect(cap).not_to have_received(:reserve!)
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
    expect(cap).to have_received(:release!).exactly(3).times
  end
end
