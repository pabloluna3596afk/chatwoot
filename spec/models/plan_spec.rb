require 'rails_helper'

RSpec.describe Plan do
  subject(:plan) { described_class.new(name: 'Catalog', slug: 'catalog') }

  it 'defaults to an empty feature list and available state' do
    expect(plan.feature_keys).to eq([])
    expect(plan.coming_soon).to be(false)
    expect(plan.catalog_state).to eq('available')
  end

  it 'accepts only arrays of supported string identifiers' do
    plan.feature_keys = described_class::FEATURE_KEYS
    expect(plan).to be_valid

    [nil, {}, 'captain_integration', [1], ['unknown'], [['automations']]].each do |invalid|
      plan.feature_keys = invalid
      expect(plan).not_to be_valid
      expect(plan.errors[:feature_keys]).to be_present
    end
  end

  it 'accepts an empty feature list' do
    plan.feature_keys = []
    expect(plan).to be_valid
  end

  it 'derives coming soon from the flag' do
    plan.coming_soon = true
    expect(plan.catalog_state).to eq('coming_soon')
  end

  it 'hides inactive, private and Developer plans even when coming soon' do
    [{ is_active: false }, { is_public: false }, { slug: 'developer' }].each do |attributes|
      hidden = described_class.new(attributes.merge(coming_soon: true))
      expect(hidden.catalog_state).to eq('hidden')
    end
  end

  it 'rejects negative or fractional daily test quotas' do
    [-1, 1.5].each do |invalid|
      plan.captain_daily_tests = invalid
      expect(plan).not_to be_valid
    end
  end
end
