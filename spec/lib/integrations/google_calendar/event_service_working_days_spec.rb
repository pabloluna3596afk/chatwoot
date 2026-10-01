require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now, connected_by: user
    )
  end
  let!(:calendar) { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:service) { described_class.new(account: account, user: user, connection: connection) }

  # 2030-01-14 is a Monday, so Saturday is the 19th and Sunday the 20th.
  def slot_dates(result)
    result.pluck(:start).map { |value| value[0, 10] }.uniq
  end

  def week_slots
    service.available_slots(calendar_id: 'cal-1', from: '2030-01-14T00:00:00-05:00', to: '2030-01-21T00:00:00-05:00', duration: 60)
  end

  def book(start_time, end_time)
    service.create({ calendar_id: 'cal-1', summary: 'Consulta', start: start_time, end: end_time }, enforce_hours: true)
  end

  around { |example| travel_to(Time.zone.parse('2030-01-10T12:00:00-05:00')) { example.run } }

  before do
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      { 'id' => 'g-1', 'etag' => '"e"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
  end

  describe '#available_slots' do
    it 'offers every day of the week by default' do
      expect(slot_dates(week_slots)).to eq(%w[2030-01-14 2030-01-15 2030-01-16 2030-01-17 2030-01-18 2030-01-19 2030-01-20])
    end

    it 'skips the days the calendar does not work' do
      calendar.update!(working_days: [1, 2, 3, 4, 5])

      expect(slot_dates(week_slots)).to eq(%w[2030-01-14 2030-01-15 2030-01-16 2030-01-17 2030-01-18])
    end

    it 'offers nothing when the whole range falls on closed days' do
      calendar.update!(working_days: [1, 2, 3, 4, 5])

      result = service.available_slots(calendar_id: 'cal-1', from: '2030-01-19T00:00:00-05:00', to: '2030-01-21T00:00:00-05:00')

      expect(result).to eq([])
    end

    it 'works with a single open day' do
      calendar.update!(working_days: [6])

      expect(slot_dates(week_slots)).to eq(['2030-01-19'])
    end

    it 'still applies the hours on the open days' do
      calendar.update!(working_days: [2], hour_start: 9, hour_end: 11)

      result = service.available_slots(calendar_id: 'cal-1', from: '2030-01-14T00:00:00-05:00', to: '2030-01-21T00:00:00-05:00')

      expect(result.pluck(:start)).to eq(%w[2030-01-15T09:00:00-05:00 2030-01-15T09:30:00-05:00 2030-01-15T10:00:00-05:00 2030-01-15T10:30:00-05:00])
    end
  end

  describe '#create with enforce_hours' do
    it 'books on a working day' do
      calendar.update!(working_days: [2])

      expect { book('2030-01-15T10:00:00-05:00', '2030-01-15T10:30:00-05:00') }.not_to raise_error
    end

    it 'rejects a booking on a closed day, inside the hours, without calling Google' do
      calendar.update!(working_days: [1, 2, 3, 4, 5])

      expect { book('2030-01-19T10:00:00-05:00', '2030-01-19T10:30:00-05:00') }.to raise_error(described_class::OutsideHours)
      expect(client).not_to have_received(:create_event)
    end

    it 'keeps accepting a closed day when enforcement is off (agents and the Panel AI bridge)' do
      calendar.update!(working_days: [1, 2, 3, 4, 5])

      expect do
        service.create({ calendar_id: 'cal-1', summary: 'Consulta', start: '2030-01-19T10:00:00-05:00', end: '2030-01-19T10:30:00-05:00' })
      end.not_to raise_error
    end
  end
end
