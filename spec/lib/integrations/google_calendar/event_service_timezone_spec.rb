require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventService do
  let(:account) { create(:account, settings: { reporting_timezone: 'America/New_York' }) }
  let(:service) { described_class.new(account: account, user: nil, connection: nil) }

  it 'rejects nonexistent local inputs rather than moving them an hour forward' do
    expect { service.send(:parse_range, start: '2030-03-10T02:30:00', end: '2030-03-10T03:30:00') }
      .to(raise_error { |error| expect(error.class.name).to eq('Integrations::GoogleCalendar::EventService::InvalidRange') })
  end

  it 'selects the earlier occurrence for a repeated local hour' do
    start_at, = service.send(:parse_range, start: '2030-11-03T01:30:00', end: '2030-11-03T02:00:00')
    expect(start_at.utc.iso8601).to eq('2030-11-03T05:30:00Z')
  end

  it 'preserves explicit offsets for either repeated occurrence' do
    %w[-04:00 -05:00].each do |offset|
      start_at, = service.send(:parse_range, start: "2030-11-03T01:30:00#{offset}", end: '2030-11-03T02:00:00-05:00')
      expect(start_at.iso8601).to eq("2030-11-03T01:30:00#{offset}")
    end
  end

  it 'interprets all-day Google dates at account midnight, preserving the civil day' do
    value = service.send(:parse_google_time, { 'date' => '2031-01-01' })
    expect(value.utc.iso8601).to eq('2031-01-01T05:00:00Z')
  end

  it 'canonicalizes Rails timezone names for Google and browser clients' do
    account.reporting_timezone = 'Eastern Time (US & Canada)'
    expect(service.account_timezone).to eq('America/New_York')
  end

  it 'retains the Guayaquil fallback for an unconfigured account' do
    account.reporting_timezone = nil
    expect(service.account_timezone).to eq('America/Guayaquil')
  end
end
