require 'rails_helper'

RSpec.describe Reports::PanelDateRange do
  let(:account) { build(:account, reporting_timezone: 'America/Guayaquil') }

  describe '.resolve' do
    {
      'today' => ['2026-10-11T05:00:00Z', '2026-10-12T04:59:59Z'],
      'yesterday' => ['2026-10-10T05:00:00Z', '2026-10-11T04:59:59Z'],
      'last_7_days' => ['2026-10-05T05:00:00Z', '2026-10-12T04:59:59Z'],
      'last_30_days' => ['2026-09-12T05:00:00Z', '2026-10-12T04:59:59Z']
    }.each do |preset, boundaries|
      it "resolves #{preset} in the account timezone, including today" do
        travel_to Time.utc(2026, 10, 12, 2) do
          Time.use_zone('UTC') do
            expect(described_class.resolve(preset, account: account).map(&:to_i)).to eq(boundaries.map { |value| Time.iso8601(value).to_i })
          end
        end
      end
    end

    it 'uses the application timezone when the account has none' do
      account.reporting_timezone = nil
      travel_to Time.utc(2026, 10, 12, 2) do
        Time.use_zone('Asia/Tokyo') do
          expect(described_class.resolve('today', account: account).map(&:to_i)).to eq(
            [Time.utc(2026, 10, 11, 15).to_i, Time.utc(2026, 10, 12, 14, 59, 59).to_i]
          )
        end
      end
    end

    it 'uses calendar days across a daylight saving transition' do
      account.reporting_timezone = 'America/New_York'
      travel_to Time.utc(2026, 3, 9, 2) do
        expect(described_class.resolve('last_7_days', account: account).map(&:to_i)).to eq(
          [Time.utc(2026, 3, 2, 5).to_i, Time.utc(2026, 3, 9, 3, 59, 59).to_i]
        )
      end
    end
  end

  describe '.validate' do
    let(:since_value) { Time.utc(2024, 1, 1, 5).to_i }

    it 'accepts exactly 366 calendar days including a leap day' do
      until_value = Time.utc(2025, 1, 1, 4, 59, 59).to_i
      expect(described_class.validate(since_value, until_value, account: account).map(&:to_i)).to eq([since_value, until_value])
    end

    it 'accepts integer query parameters and a single instant' do
      expect(described_class.validate('0', '0', account: account).map(&:to_i)).to eq([0, 0])
    end

    [nil, '', '123abc', '1.5', 1.5, true, [], {}].each do |invalid|
      it "rejects invalid timestamps #{invalid.inspect}" do
        expect { described_class.validate(invalid, since_value, account: account) }
          .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
      end
    end

    it 'rejects reversed and oversized custom ranges' do
      [since_value - 1, Time.utc(2025, 1, 1, 5).to_i].each do |until_value|
        expect { described_class.resolve('custom', custom_since: since_value, custom_until: until_value, account: account) }
          .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
      end
    end
  end
end
