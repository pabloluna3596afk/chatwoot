require 'rails_helper'

RSpec.describe AccountExtraBalance do
  let(:account) { create(:account) }

  it 'grants an external reference only once' do
    attributes = { bucket: :internal, units: 10, source: :purchase, expires_at: 90.days.from_now, external_reference: 'payment-123' }
    first = account.grant_extra_balance!(**attributes)
    second = account.grant_extra_balance!(**attributes)
    expect(second).to eq(first)
    expect(account.account_extra_balances.count).to eq(1)
    expect(first.units_remaining).to eq(10)
  end

  it 'does not expose another account balance through a reused reference' do
    attributes = { bucket: :internal, units: 10, source: :manual, expires_at: 1.day.from_now, external_reference: 'shared' }
    account.grant_extra_balance!(**attributes)
    other = create(:account)
    expect { other.grant_extra_balance!(**attributes) }.to raise_error(ArgumentError, /another account/)
  end

  it 'rejects unsupported buckets, sources, nonpositive units and pack mismatches' do
    pack = ExtraPack.create!(bucket: :copilot, units: 1000, price_usd: 5)
    balance = described_class.new(account: account, bucket: 'other', source: 'other', units_total: 0, units_remaining: -1)
    expect(balance).not_to be_valid
    expect(balance.errors.attribute_names).to include(:bucket, :source, :units_total, :units_remaining, :expires_at)
    balance.assign_attributes(bucket: :internal, source: :courtesy, units_total: 10, units_remaining: 10,
                              expires_at: 1.day.from_now, extra_pack: pack)
    expect(balance).not_to be_valid
    expect(balance.errors[:bucket]).to be_present
  end

  it 'rejects malformed units at the grant boundary' do
    expect do
      account.grant_extra_balance!(bucket: :internal, units: '10', source: :courtesy, expires_at: 1.day.from_now)
    end.to raise_error(ArgumentError, /positive integer/)
  end
end
