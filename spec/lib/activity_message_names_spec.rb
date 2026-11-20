require 'rails_helper'

RSpec.describe ActivityMessageNames do
  it 'keeps literal spelling, removes duplicates and blanks, and orders by the text' do
    expect(described_class.attributes('Ana assigned Pablo to VIP', 'Pablo', nil, '', 'Ana', 'VIP', 'Pablo', 'ana', 'Other'))
      .to eq(activity: { names: %w[Ana Pablo VIP] })
  end

  it 'does not split names or treat HTML as markup' do
    expect(described_class.attributes('A <B> added VIP, Gold', 'A <B>', %w[VIP Gold]))
      .to eq(activity: { names: ['A <B>', 'VIP', 'Gold'] })
  end
end
