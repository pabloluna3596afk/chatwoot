require 'rails_helper'

RSpec.describe 'Plan catalog base capabilities', type: :model do
  it 'is a short list with unique customer-facing keys' do
    keys = Plan::CATALOG_BASE_CAPABILITIES.pluck(:key)

    expect(keys.length).to be_between(1, 8)
    expect(keys.uniq).to eq(keys)
    expect(Plan::CATALOG_BASE_CAPABILITIES).to all(include(:key, :flags))
  end

  it 'uses only enabled base flags that plan features cannot turn off' do
    flags = Plan::CATALOG_BASE_CAPABILITIES.flat_map { |capability| capability[:flags] }

    flags.each do |flag|
      feature_flag = Featurable::FEATURE_LIST.find { |feature| feature['name'] == flag }

      expect(feature_flag).to include('enabled' => true)
      expect(Plan::PLAN_FLAGS).not_to include(flag)
      expect(Plans::AccountFeatureSync::BASE_FLAGS).to include(flag)
    end
  end

  it 'cannot be contradicted by the plan seed or its gated feature keys' do
    plan_seed = Rails.root.join('lib/tasks/plans.rake').read
    seeded_feature_matrix = Rails.root.join('lib/tasks/plan_feature_sync.rake').read
    capability_keys = Plan::CATALOG_BASE_CAPABILITIES.pluck(:key)
    capability_flags = Plan::CATALOG_BASE_CAPABILITIES.flat_map { |capability| capability[:flags] }

    expect(plan_seed).not_to match(/feature_keys\s*:/)
    expect(Plan::FEATURE_KEYS & capability_keys).to be_empty
    expect(Plan::PLAN_FLAGS & capability_flags).to be_empty
    capability_keys.each { |key| expect(seeded_feature_matrix).not_to include(key) }
  end
end
