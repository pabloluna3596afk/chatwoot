require 'rails_helper'

RSpec.describe ExtraPack do
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
