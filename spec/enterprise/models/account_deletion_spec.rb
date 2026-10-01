require 'rails_helper'

# The fork's tables (task templates and tasks, calendars, plan usage...) reference accounts with foreign keys, and
# the models delete them with dependent: :destroy_async, which runs after the account row is gone. The database
# deletes (or detaches) those rows itself (migration 20261001160000), so deleting an account works.
RSpec.describe Account, 'deletion' do
  let(:account) { create(:account) }

  def calendar_event_for(account)
    connection = CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now
    )
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    connection.calendar_events.create!(
      account: account, external_calendar_id: 'cal-1', google_event_id: 'g-1', summary: 'Cita',
      start_at: 1.day.from_now, end_at: 1.day.from_now + 30.minutes
    )
  end

  it 'has seeded task templates, which used to make every deletion fail' do
    expect(account.task_templates).to be_present

    expect { account.destroy! }.not_to raise_error
    expect(TaskTemplate.where(account_id: account.id)).to be_empty
  end

  it 'deletes the calendar rows and the plan usage of the account' do
    put_account_on_plan(account)
    event = calendar_event_for(account)
    connection_id = event.calendar_connection_id

    expect { account.destroy! }.not_to raise_error

    expect(CalendarEvent.where(id: event.id)).to be_empty
    expect(CalendarConnection.where(id: connection_id)).to be_empty
    expect(AccountPlanUsage.where(account_id: account.id)).to be_empty
  end

  it 'deletes the rows of a conversation that a calendar event points to' do
    conversation = create(:conversation, account: account)
    event = calendar_event_for(account)
    event.update!(conversation: conversation, contact: conversation.contact)

    expect { account.destroy! }.not_to raise_error
    expect(CalendarEvent.where(id: event.id)).to be_empty
  end
end
