require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::BookingLock, :real_redis do
  let(:lock) { described_class.new(account_id: 123, calendar_id: 'lease-spec') }
  let(:competitor) { described_class.new(account_id: 123, calendar_id: 'lease-spec') }
  let(:key) { format(Redis::RedisKeys::CALENDAR_BOOKING_LOCK, account_id: 123, calendar_id: 'lease-spec') }

  after do
    lock.release
    competitor.release
  end

  it 'keeps a slow operation exclusive beyond the original twenty second TTL' do
    expect(lock.acquire).to be_truthy
    sleep 21

    expect(Redis::Alfred.ttl(key)).to be_positive
    expect(competitor.acquire).to be_falsey
    expect { lock.assert_owned! }.not_to raise_error
  end

  it 'detects replacement and never deletes the replacement token' do
    lock.acquire
    Redis::Alfred.delete(key)
    expect(competitor.acquire).to be_truthy
    replacement = Redis::Alfred.get(key)

    expect { lock.assert_owned! }.to(raise_error { |error| expect(error.class.name).to eq("#{described_class}::Lost") })
    lock.release

    expect(Redis::Alfred.get(key)).to eq(replacement)
  end

  it 'does not renew a replacement during its heartbeat' do
    stub_const("#{described_class}::HEARTBEAT_INTERVAL", 0.05)
    lock.acquire
    Redis::Alfred.set(key, 'replacement', ex: 2)
    sleep 0.2

    expect(Redis::Alfred.ttl(key)).to be <= 2
    expect { lock.assert_owned! }.to(raise_error { |error| expect(error.class.name).to eq("#{described_class}::Lost") })
    lock.release
    expect(Redis::Alfred.get(key)).to eq('replacement')
  end

  it 'fails closed on a Redis outage even after connectivity returns' do
    lock.acquire
    allow(Redis::Alfred).to receive(:with).and_raise(Redis::BaseError)
    expect { lock.assert_owned! }.to(raise_error { |error| expect(error.class.name).to eq("#{described_class}::Lost") })
    allow(Redis::Alfred).to receive(:with).and_call_original

    expect { lock.assert_owned! }.to(raise_error { |error| expect(error.class.name).to eq("#{described_class}::Lost") })
  end

  it 'remembers a heartbeat failure even if the old token reappears' do
    stub_const("#{described_class}::HEARTBEAT_INTERVAL", 0.05)
    lock.acquire
    token = Redis::Alfred.get(key)
    Redis::Alfred.set(key, 'replacement', ex: 20)
    sleep 0.2
    Redis::Alfred.set(key, token, ex: 20)

    expect { lock.assert_owned! }.to(raise_error { |error| expect(error.class.name).to eq("#{described_class}::Lost") })
  end
end
