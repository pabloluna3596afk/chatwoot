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
  let(:day_start) { '2030-01-15T00:00:00-05:00' }
  let(:day_end) { '2030-01-16T00:00:00-05:00' }

  def slots(overrides = {})
    service.available_slots(**{ calendar_id: 'cal-1', from: day_start, to: day_end, duration: 30 }.merge(overrides))
  end

  def starts(result)
    result.pluck(:start).map { |value| value[11, 5] }
  end

  def local_event(attrs = {})
    connection.calendar_events.create!(
      {
        account: account, external_calendar_id: 'cal-1', google_event_id: "local-#{SecureRandom.hex(4)}", summary: 'Existing',
        start_at: Time.zone.parse('2030-01-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:30:00-05:00')
      }.merge(attrs)
    )
  end

  def google_busy(start_time, end_time, extra = {})
    { 'id' => "ext-#{SecureRandom.hex(3)}", 'summary' => 'Busy', 'status' => 'confirmed',
      'start' => { 'dateTime' => start_time }, 'end' => { 'dateTime' => end_time } }.merge(extra)
  end

  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00-05:00')) { example.run } }

  before do
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**kwargs|
      { 'id' => 'g-1', 'etag' => '"e"', 'summary' => kwargs[:summary],
        'start' => { 'dateTime' => kwargs[:start_at].iso8601 }, 'end' => { 'dateTime' => kwargs[:end_at].iso8601 } }
    end
  end

  describe '#available_slots' do
    it 'offers back-to-back slots across the calendar hours (08:00-20:00 by default) in the account timezone' do
      result = slots

      expect(result.size).to eq(24)
      expect(result.first).to eq(start: '2030-01-15T08:00:00-05:00', end: '2030-01-15T08:30:00-05:00')
      expect(result.last).to eq(start: '2030-01-15T19:30:00-05:00', end: '2030-01-15T20:00:00-05:00')
    end

    it 'never offers a slot that ends after the closing hour' do
      result = slots(duration: 50)

      expect(result.size).to eq(14)
      expect(result.last[:end]).to eq('2030-01-15T19:40:00-05:00')
    end

    it 'fits a slot that ends exactly at the closing hour' do
      result = slots(duration: 45)

      expect(result.size).to eq(16)
      expect(result.last[:end]).to eq('2030-01-15T20:00:00-05:00')
    end

    it 'uses the hours configured on the calendar' do
      calendar.update!(hour_start: 9, hour_end: 12)

      expect(starts(slots)).to eq(%w[09:00 09:30 10:00 10:30 11:00 11:30])
    end

    it 'covers every day of a multi-day range' do
      result = slots(to: '2030-01-18T00:00:00-05:00')

      expect(result.size).to eq(72)
      expect(result.pluck(:start).map { |value| value[0, 10] }.uniq).to eq(%w[2030-01-15 2030-01-16 2030-01-17])
    end

    it 'cuts slots at the end of the requested range' do
      result = slots(from: '2030-01-15T09:00:00-05:00', to: '2030-01-15T10:00:00-05:00')

      expect(starts(result)).to eq(%w[09:00 09:30])
    end

    it 'starts at the opening hour when the range starts earlier' do
      result = slots(to: '2030-01-15T09:00:00-05:00')

      expect(starts(result)).to eq(%w[08:00 08:30])
    end

    it 'skips a slot that overlaps a kept local event and keeps the back-to-back neighbours' do
      local_event

      expect(starts(slots)).to include('09:30', '10:30')
      expect(starts(slots)).not_to include('10:00')
    end

    it 'blocks every slot that a longer event touches' do
      local_event(start_at: Time.zone.parse('2030-01-15T10:15:00-05:00'), end_at: Time.zone.parse('2030-01-15T11:15:00-05:00'))

      expect(starts(slots)).not_to include('10:00', '10:30', '11:00')
      expect(starts(slots)).to include('09:30', '11:30')
    end

    it 'ignores cancelled local events' do
      local_event(deleted_at: Time.current)

      expect(starts(slots)).to include('10:00')
    end

    it 'skips slots that overlap a busy Google event' do
      allow(client).to receive(:list_events).and_return([google_busy('2030-01-15T14:00:00-05:00', '2030-01-15T15:00:00-05:00')])

      result = starts(slots)

      expect(result).not_to include('14:00', '14:30')
      expect(result).to include('13:30', '15:00')
    end

    it 'ignores cancelled and transparent Google events' do
      allow(client).to receive(:list_events).and_return(
        [google_busy('2030-01-15T11:00:00-05:00', '2030-01-15T12:00:00-05:00', 'status' => 'cancelled'),
         google_busy('2030-01-15T13:00:00-05:00', '2030-01-15T14:00:00-05:00', 'transparency' => 'transparent')]
      )

      expect(starts(slots)).to include('11:00', '11:30', '13:00', '13:30')
    end

    it 'asks Google once for the whole range' do
      slots(to: '2030-01-18T00:00:00-05:00')

      expect(client).to have_received(:list_events).once.with(
        calendar_id: 'cal-1', time_min: '2030-01-15T00:00:00-05:00', time_max: '2030-01-18T00:00:00-05:00'
      )
    end

    context 'with a minimum notice' do
      let(:today_start) { '2030-01-14T00:00:00-05:00' }
      let(:today_end) { '2030-01-15T00:00:00-05:00' }

      it 'drops slots that start before now plus the notice, keeping the one that starts exactly at the limit' do
        result = slots(from: today_start, to: today_end, min_notice_minutes: 60)

        expect(starts(result).first).to eq('13:00')
      end

      it 'rounds the first slot up to the next slot boundary' do
        result = slots(from: today_start, to: today_end, min_notice_minutes: 90)

        expect(starts(result).first).to eq('13:30')
      end

      it 'never offers slots in the past even with no notice' do
        result = slots(from: today_start, to: today_end, min_notice_minutes: 0)

        expect(starts(result).first).to eq('12:00')
      end
    end

    it 'uses the account timezone' do
      account.update!(reporting_timezone: 'Asia/Kolkata')

      result = slots(from: '2030-01-15T00:00:00+05:30', to: '2030-01-16T00:00:00+05:30')

      expect(result.first[:start]).to eq('2030-01-15T08:00:00+05:30')
      expect(result.last[:end]).to eq('2030-01-15T20:00:00+05:30')
    end

    it 'accepts times as Time objects' do
      result = slots(from: Time.zone.parse(day_start), to: Time.zone.parse(day_end))

      expect(result.size).to eq(24)
    end

    it 'rejects a calendar that is not enabled' do
      calendar.update!(is_enabled: false)

      expect { slots }.to raise_error(described_class::CalendarNotEnabled)
    end

    it 'rejects an empty range or a non-positive duration' do
      expect { slots(to: day_start) }.to raise_error(described_class::InvalidRange)
      expect { slots(duration: 0) }.to raise_error(described_class::InvalidRange)
    end
  end

  describe '#create with enforce_hours' do
    def book(start_time, end_time, **options)
      service.create({ calendar_id: 'cal-1', summary: 'Consulta', start: start_time, end: end_time }, **options)
    end

    it 'books inside the calendar hours' do
      expect { book('2030-01-15T19:30:00-05:00', '2030-01-15T20:00:00-05:00', enforce_hours: true) }.not_to raise_error
    end

    it 'rejects a start before the opening hour without calling Google' do
      expect { book('2030-01-15T07:30:00-05:00', '2030-01-15T08:00:00-05:00', enforce_hours: true) }
        .to raise_error(described_class::OutsideHours)
      expect(client).not_to have_received(:create_event)
    end

    it 'rejects an end after the closing hour' do
      expect { book('2030-01-15T19:45:00-05:00', '2030-01-15T20:15:00-05:00', enforce_hours: true) }
        .to raise_error(described_class::OutsideHours)
    end

    it 'rejects a booking that spans two days' do
      expect { book('2030-01-15T19:45:00-05:00', '2030-01-16T08:15:00-05:00', enforce_hours: true) }
        .to raise_error(described_class::OutsideHours)
    end

    it 'keeps accepting any hour when enforcement is off (agents and the Panel AI bridge)' do
      expect { book('2030-01-15T07:30:00-05:00', '2030-01-15T08:00:00-05:00') }.not_to raise_error
    end

    it 'follows the calendar hours when they change' do
      calendar.update!(hour_start: 6, hour_end: 9)

      expect { book('2030-01-15T07:30:00-05:00', '2030-01-15T08:00:00-05:00', enforce_hours: true) }.not_to raise_error
    end
  end
end
