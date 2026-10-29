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

  it 'defines bilingual feature metadata and maps each catalog key to account flags' do
    expect(described_class::FEATURES).to all(include(:key, :label_en, :label_es, :description_en, :description_es, :group, :flags))
    expect(described_class::FEATURE_KEYS).to match_array(described_class::FEATURES.pluck(:key))
    expect(described_class::FEATURES.flat_map { |feature| feature[:flags] }).to all(be_in(Featurable::FEATURE_LIST.pluck('name')))
  end

  it 'accepts an empty feature list' do
    plan.feature_keys = []
    expect(plan).to be_valid
  end

  it 'shows Copilot from the response allowance, including shared unlimited allowance' do
    expect(plan.copilot_available?).to be(true)
    plan.captain_copilot_responses = 0
    expect(plan.copilot_available?).to be(false)
    plan.captain_copilot_responses = 20
    expect(plan.copilot_available?).to be(true)
  end

  it 'queues account synchronization when plan features change' do
    plan.save!

    expect { plan.update!(feature_keys: ['automations']) }
      .to have_enqueued_job(Plans::SyncPlanAccountsJob).with(plan.id)
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

  it 'defines bilingual metadata and reads every registered limit from columns or JSONB' do
    expect(described_class::LIMITS).to all(include(:key, :group, :label_en, :label_es, :unit_en, :unit_es, :help_en, :help_es, :enforcement))

    described_class::LIMITS.each do |definition|
      key = definition[:key]
      plan.limit_values = { key => '17' }
      expect(plan.limit(key)).to eq(17), "expected #{key} to read its configured value"
    end
  end

  it 'treats an absent JSONB value and a NULL column value as unlimited' do
    described_class::LIMITS.select { |definition| definition[:column].nil? }.each do |definition|
      expect(plan.limit(definition[:key])).to be_nil
    end
    plan.limit_values = { storage_mb: '' }
    expect(plan.limit(:storage_mb)).to be_nil
    expect(plan.unlimited_limit?(:storage_mb)).to be(true)
  end

  it 'rejects non-integer and negative dynamic limits' do
    plan.limit_values = { max_flows: '2.5' }
    expect(plan).not_to be_valid

    plan = described_class.new(name: 'Catalog', slug: 'catalog')
    plan.limit_values = { max_flows: '-1' }
    expect(plan).not_to be_valid
  end
end
