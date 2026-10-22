require 'rails_helper'

RSpec.describe Calendar::CustomerReminders::Dispatcher, 'concurrent workers' do
  # Separate connections must see committed rows; the default per-example transaction would hide the fixture.
  self.use_transactional_tests = false

  let(:now) { Time.utc(2030, 1, 14, 15) }
  let(:account) { create(:account, locale: 'es', reporting_timezone: 'UTC', customer_reminders_enabled: true) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [{ 'name' => 'cita_recordatorio', 'language' => 'es', 'status' => 'APPROVED' }])
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:connection) { create(:calendar_connection, account: account) }
  let(:cap) { instance_double(Automations::ProactiveSendCap, reserve!: true) }

  before do
    travel_to(now)
    allow(Automations::ProactiveSendCap).to receive(:new).and_return(cap)
  end

  after do
    account.destroy!
    travel_back
  end

  it 'R1 lets two real database connections claim only one outgoing reminder' do
    event = create(:calendar_event, calendar_connection: connection, conversation: conversation,
                                    start_at: now + 24.hours, created_at: now - 2.days)
    ready = Queue.new
    start = Queue.new
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          described_class.new(now: now).perform
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)

    expect(conversation.messages.outgoing.count).to eq(1)
    expect(event.reload.customer_reminder_status).to eq('queued_1')
    expect(cap).to have_received(:reserve!).once
  end
end
