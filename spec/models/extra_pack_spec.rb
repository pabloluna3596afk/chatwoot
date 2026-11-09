require 'rails_helper'

RSpec.describe ExtraPack do
  it 'seeds the approved catalog without overwriting administrative edits' do
    described_class.seed_defaults!
    expect(described_class.order(:bucket, :units).pluck(:bucket, :units, :price_usd)).to eq([
      ['captain_responses', 500, 20], ['captain_responses', 2000, 64], ['captain_responses', 5000, 140],
      ['copilot', 1000, 5], ['copilot', 5000, 20],
      ['internal', 500, 6], ['internal', 2000, 20], ['internal', 5000, 45]
    ])
    pack = described_class.find_by!(bucket: :internal, units: 500)
    pack.update!(price_usd: 9, active: false)
    described_class.seed_defaults!
    expect(pack.reload).to have_attributes(price_usd: 9, active: false)
    expect(described_class.count).to eq(8)
  end

  it 'validates bucket, units and price' do
    pack = described_class.new(bucket: 'other', units: 0, price_usd: -1)
    expect(pack).not_to be_valid
    expect(pack.errors.attribute_names).to include(:bucket, :units, :price_usd)
  end

  it 'prevents duplicate pack sizes per bucket and preserves purchased packs' do
    pack = described_class.create!(bucket: :internal, units: 500, price_usd: 6)
    expect(described_class.new(bucket: :internal, units: 500, price_usd: 7)).not_to be_valid
    account = create(:account)
    account.grant_extra_balance!(bucket: :internal, units: 500, source: :purchase, expires_at: 90.days.from_now, extra_pack: pack)
    expect(pack.destroy).to be(false)
  end
end
