require 'rails_helper'

RSpec.describe CalendarEvent, 'customer reminders' do
  let(:now) { Time.utc(2030, 1, 14, 15) }
  let(:account) { create(:account, customer_reminders_enabled: true) }
  let(:connection) { create(:calendar_connection, account: account) }
  let(:event) { create(:calendar_event, calendar_connection: connection, start_at: now + 2.days) }

  before { travel_to(now) }
  after { travel_back }

  it 'clears both markers when the start changes' do
    event.update!(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
    event.update!(start_at: now + 3.days)
    expect(event.reload).to have_attributes(customer_reminder_status: nil, customer_reminder_sent_at: nil)
  end

  it 'keeps the markers on unrelated edits' do
    event.update!(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
    event.update!(summary: 'Updated')
    expect(event.reload).to have_attributes(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
  end

  it 'marks a new appointment with less than 24 hours of notice' do
    event = create(:calendar_event, calendar_connection: connection, start_at: now + 23.hours)
    expect(event.customer_reminder_status).to eq('skipped_too_close')
  end

  it 'allows exactly 24 hours of notice' do
    event = create(:calendar_event, calendar_connection: connection, start_at: now + 24.hours)
    expect(event.customer_reminder_status).to be_nil
  end

  it 'reevaluates too close when moved in either direction' do
    event.update!(start_at: now + 23.hours)
    expect(event.reload.customer_reminder_status).to eq('skipped_too_close')
    event.update!(start_at: now + 3.days)
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'does not mark appointments while disabled, including on creation' do
    account.update!(customer_reminders_enabled: false)
    event = create(:calendar_event, calendar_connection: connection, start_at: now + 2.hours)
    expect(event.customer_reminder_status).to be_nil
    event.update!(start_at: now + 3.hours)
    expect(event.reload.customer_reminder_status).to be_nil
  end

  it 'does not mark Captain or Panel AI appointments' do
    ai = create(:calendar_event, calendar_connection: connection, start_at: now + 2.hours, booking_source: 'ai')
    panel = create(:calendar_event, calendar_connection: connection, start_at: now + 2.hours, bot_followup_policy: { 'enabled' => true })
    expect(ai.customer_reminder_status).to be_nil
    expect(panel.customer_reminder_status).to be_nil
  end

  it 'selects only nonterminal reminders' do
    event
    sent = create(:calendar_event, calendar_connection: connection, start_at: now + 2.days)
    sent.update!(customer_reminder_status: 'sent', customer_reminder_sent_at: now)
    expect(described_class.customer_reminder_pending).to include(event)
    expect(described_class.customer_reminder_pending).not_to include(sent)
  end
end
