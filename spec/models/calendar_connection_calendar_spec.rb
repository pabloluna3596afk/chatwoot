require 'rails_helper'

RSpec.describe CalendarConnectionCalendar, type: :model do
  let(:account) { create(:account) }
  let(:connection) { CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'r') }
  let(:calendar) { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }

  describe 'working_days' do
    it 'defaults to every day of the week' do
      expect(calendar.reload.working_days).to eq([0, 1, 2, 3, 4, 5, 6])
    end

    it 'accepts any non-empty set of weekdays' do
      calendar.working_days = [1, 2, 3, 4, 5]

      expect(calendar).to be_valid
    end

    it 'rejects an empty list' do
      calendar.working_days = []

      expect(calendar).not_to be_valid
      expect(calendar.errors[:working_days]).to be_present
    end

    it 'rejects days outside 0-6 and duplicates' do
      [[7], [-1], [1, 1]].each do |days|
        calendar.working_days = days
        expect(calendar).not_to be_valid, "expected #{days.inspect} to be invalid"
      end
    end
  end

  describe '#works_on?' do
    it 'tells whether a weekday (Date#wday) is a working day' do
      calendar.update!(working_days: [1, 3])

      expect([0, 1, 2, 3, 4, 5, 6].select { |wday| calendar.works_on?(wday) }).to eq([1, 3])
    end
  end
end
