require 'rails_helper'

RSpec.describe Calendar::CustomerReminders::Schedule do
  %w[America/Guayaquil UTC].each do |timezone|
    context "with an account in #{timezone}" do
      let(:account) { build(:account, reporting_timezone: timezone) }
      let(:zone) { Time.find_zone!(timezone) }

      { '07:59' => '2030-01-13 21:00', '08:00' => '2030-01-14 08:00',
        '20:59' => '2030-01-14 20:59', '21:00' => '2030-01-14 21:00',
        '21:01' => '2030-01-14 21:00', '00:00' => '2030-01-13 21:00' }.each do |time, expected|
        it "R11 advances #{time} to #{expected}" do
          event = build(:calendar_event, account: account, start_at: zone.parse("2030-01-15 #{time}"))
          expect(described_class.due_at(event)).to eq(zone.parse(expected))
          expect(described_class.due_at(event)).to be < event.start_at
        end
      end

      { '07:59' => false, '08:00' => true, '20:59' => true, '21:00' => true, '21:01' => false, '00:00' => false }.each do |time, allowed|
        it "permits sending at #{time}: #{allowed}" do
          expect(described_class.sending_hours?(account, zone.parse("2030-01-14 #{time}"))).to be(allowed)
        end
      end
    end
  end
end
