require 'rails_helper'

RSpec.describe Calendar::CustomerReminders::Delivery do
  around { |example| Time.use_zone('UTC') { example.run } }

  let(:now) { Time.utc(2030, 1, 14, 15) }
  let(:account) { create(:account, locale: 'es', reporting_timezone: 'UTC', customer_reminders_enabled: true) }
  let(:templates) do
    [{ 'name' => 'cita_recordatorio', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY' }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:event) do
    create(:calendar_event, calendar_connection: create(:calendar_connection, account: account), conversation: conversation,
                            start_at: now + 24.hours, created_at: now - 2.days)
  end
  let(:service) { instance_double(Whatsapp::SendOnWhatsappService) }
  let(:outgoing) { conversation.messages.outgoing.reorder(:id) }

  before do
    travel_to(now)
    allow(Automations::ProactiveSendCap).to receive(:new).and_call_original
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(service)
    allow(service).to receive(:perform)
    event
    Calendar::CustomerReminders::Dispatcher.new.perform
  end

  it 'R1 marks sent only after Meta accepts and ignores duplicate delivery jobs' do
    allow(service).to receive(:perform) { outgoing.last.update!(source_id: 'wamid-accepted') }
    2.times { SendReplyJob.perform_now(outgoing.last.id) }
    expect(event.reload).to have_attributes(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
    expect(service).to have_received(:perform).once
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'R14 releases the claim after provider rejection, stops at three and never raises into the scheduler' do
    allow(service).to receive(:perform) { outgoing.last.update!(status: :failed) }
    3.times do |index|
      SendReplyJob.perform_now(outgoing.last.id)
      expected = index == 2 ? 'skipped_error' : "retry_#{index + 1}"
      expect(event.reload.customer_reminder_status).to eq(expected)
      Calendar::CustomerReminders::Dispatcher.new.perform
    end
    expect(outgoing.count).to eq(3)
    expect(event.reload.customer_reminder_sent_at).to be_nil
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'R14 catches network errors without logging their sensitive message' do
    allow(service).to receive(:perform).and_raise(StandardError, 'secret token and phone')
    allow(Rails.logger).to receive(:error)
    SendReplyJob.perform_now(outgoing.last.id)
    expect(event.reload.customer_reminder_status).to eq('retry_1')
    expect(Rails.logger).to have_received(:error).with(/StandardError/)
    expect(Rails.logger).not_to have_received(:error).with(/secret token/)
  end

  it 'retains the retry budget if the template becomes unavailable between attempts' do
    allow(service).to receive(:perform) { outgoing.last.update!(status: :failed) }
    SendReplyJob.perform_now(outgoing.last.id)
    channel.update!(message_templates: [])
    2.times { Calendar::CustomerReminders::Dispatcher.new.perform }
    expect(event.reload.customer_reminder_status).to eq('retry_1')
    expect(conversation.messages.activity.count).to eq(1)
    channel.update!(message_templates: [{ 'name' => 'cita_recordatorio', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY' }])
    Calendar::CustomerReminders::Dispatcher.new.perform
    expect(event.reload.customer_reminder_status).to eq('queued_2')
  end

  it 'ignores a job for the old time after a reschedule without overwriting the new markers' do
    message = outgoing.last
    event.reload.update!(start_at: now + 2.hours)
    SendReplyJob.perform_now(message.id)
    expect(event.reload.customer_reminder_status).to eq('skipped_too_close')
    expect(service).not_to have_received(:perform)
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'rechecks the switch when the queue was delayed' do
    account.update!(customer_reminders_enabled: false)
    SendReplyJob.perform_now(outgoing.last.id)
    expect(service).not_to have_received(:perform)
    expect(event.reload.customer_reminder_status).to be_nil
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'does not send a queued reminder after its template becomes MARKETING' do
    channel.update!(message_templates: [{ 'name' => 'cita_recordatorio', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'MARKETING' }])
    SendReplyJob.perform_now(outgoing.last.id)
    expect(service).not_to have_received(:perform)
    expect(event.reload.customer_reminder_status).to be_nil
    Calendar::CustomerReminders::Dispatcher.new.perform
    expect(event.reload.customer_reminder_status).to eq('no_template')
  end

  it 'rechecks cancellation before delivery' do
    event.update!(appointment_status: 'cancelled')
    SendReplyJob.perform_now(outgoing.last.id)
    expect(service).not_to have_received(:perform)
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end

  it 'rechecks confirmation before delivery' do
    event.update!(appointment_status: 'confirmed')
    SendReplyJob.perform_now(outgoing.last.id)
    expect(service).not_to have_received(:perform)
    Calendar::CustomerReminders::Dispatcher.new.perform
    expect(event.reload.customer_reminder_status).to eq('skipped_confirmed')
  end

  it 'waits until morning if the send queue only resumes overnight' do
    travel_to(Time.utc(2030, 1, 14, 23))
    SendReplyJob.perform_now(outgoing.last.id)
    expect(service).not_to have_received(:perform)
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'delivers queued messages both with yesterday cap_date and without cap_date' do
    previous_message = outgoing.last
    previous_attributes = previous_message.additional_attributes
    previous_attributes['customer_reminder']['cap_date'] = (now.to_date - 1).iso8601
    previous_message.update!(additional_attributes: previous_attributes)
    allow(service).to receive(:perform) { previous_message.update!(source_id: 'wamid-old') }
    SendReplyJob.perform_now(previous_message.id)
    expect(event.reload.customer_reminder_status).to eq('sent')

    second_event = create(:calendar_event, calendar_connection: event.calendar_connection, conversation: conversation,
                                           start_at: now + 24.hours, created_at: now - 2.days)
    Calendar::CustomerReminders::Dispatcher.new.perform
    second_message = outgoing.where.not(id: previous_message.id).last
    allow(service).to receive(:perform) { second_message.update!(source_id: 'wamid-new') }
    SendReplyJob.perform_now(second_message.id)
    expect(second_event.reload.customer_reminder_status).to eq('sent')
    expect(second_message.additional_attributes['customer_reminder']).not_to have_key('cap_date')
    expect(Automations::ProactiveSendCap).not_to have_received(:new)
  end
end
