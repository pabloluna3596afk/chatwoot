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

  it 'defaults to no daily free tests' do
    expect(plan.captain_daily_tests).to eq(0)
  end

  it 'accepts a nonnegative integer allowance' do
    plan.captain_daily_tests = 35
    expect(plan).to be_valid
  end

  it 'rejects negative, fractional and missing allowances' do
    [-1, 1.5, nil].each do |value|
      plan.captain_daily_tests = value
      expect(plan).not_to be_valid
      expect(plan.errors[:captain_daily_tests]).to be_present
    end
  end

  it 'allows AI usage limits to remain unconfigured or be nonnegative integers' do
    expect(plan).to be_valid

    plan.assign_attributes(captain_copilot_responses: 20, captain_internal_calls: 100)
    expect(plan).to be_valid

    plan.captain_internal_calls = -1
    expect(plan).not_to be_valid
  end
end
