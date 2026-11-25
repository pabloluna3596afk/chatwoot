require 'rails_helper'

RSpec.describe AutomationRules::TimeWindow do
  describe '.parse' do
    ['00:00-23:59', '18:00-08:00', '09:00-13:00|mon', '22:00-06:00|fri,sat', '09:00-17:00|sun,mon,tue,wed,thu,fri,sat'].each do |value|
      it "accepts #{value}" do
        expect(described_class.parse(value)).to be_a(described_class)
      end
    end

    [nil, '', 18, ['18:00-08:00'], '18:00', '18:00-', '8:00-18:00', '24:00-08:00', '18:60-19:00', '18:00-08:00|', '18:00-08:00|xyz',
     '18:00-08:00|mon,mon', '18:00-08:00|mon,', '18:00-08:00|MON', '09:00-09:00', '18:00 - 08:00', "18:00-08:00\n"].each do |value|
      it "rejects #{value.inspect}" do
        expect(described_class.parse(value)).to be_nil
      end
    end

    it 'reads hours, crossing and weekdays' do
      window = described_class.parse('22:30-06:15|fri,sat')

      expect(window.start_minute).to eq((22 * 60) + 30)
      expect(window.end_minute).to eq((6 * 60) + 15)
      expect(window.crosses_midnight?).to be(true)
      expect(window.wdays).to eq([5, 6])
    end
  end

  describe '#cover?' do
    let(:zone) { ActiveSupport::TimeZone['UTC'] }

    def at(text)
      zone.parse(text)
    end

    it 'includes the start and excludes the end of a same-day window' do
      window = described_class.parse('09:00-13:00')

      expect(window.cover?(at('2026-10-26 08:59'))).to be(false)
      expect(window.cover?(at('2026-10-26 09:00'))).to be(true)
      expect(window.cover?(at('2026-10-26 12:59'))).to be(true)
      expect(window.cover?(at('2026-10-26 13:00'))).to be(false)
    end

    it 'covers both sides of midnight when the window crosses it' do
      window = described_class.parse('18:00-08:00')

      expect(window.cover?(at('2026-10-26 17:59'))).to be(false)
      expect(window.cover?(at('2026-10-26 18:00'))).to be(true)
      expect(window.cover?(at('2026-10-26 23:59'))).to be(true)
      expect(window.cover?(at('2026-10-27 00:00'))).to be(true)
      expect(window.cover?(at('2026-10-27 07:59'))).to be(true)
      expect(window.cover?(at('2026-10-27 08:00'))).to be(false)
    end

    it 'uses the weekday on which the window starts' do
      # 2026-10-23 is a Friday.
      window = described_class.parse('22:00-06:00|fri')

      expect(window.cover?(at('2026-10-23 21:59'))).to be(false)
      expect(window.cover?(at('2026-10-23 22:00'))).to be(true)
      expect(window.cover?(at('2026-10-24 05:59'))).to be(true)
      expect(window.cover?(at('2026-10-24 22:00'))).to be(false)
      expect(window.cover?(at('2026-10-23 05:59'))).to be(false)
    end

    it 'treats the early morning of Sunday as part of a Saturday window' do
      window = described_class.parse('22:00-06:00|sat')

      expect(window.cover?(at('2026-10-25 02:00'))).to be(true)
      expect(window.cover?(at('2026-10-26 02:00'))).to be(false)
    end

    it 'applies weekdays to a same-day window' do
      window = described_class.parse('09:00-13:00|mon,wed')

      expect(window.cover?(at('2026-10-26 10:00'))).to be(true)
      expect(window.cover?(at('2026-10-27 10:00'))).to be(false)
      expect(window.cover?(at('2026-10-28 10:00'))).to be(true)
    end
  end
end
