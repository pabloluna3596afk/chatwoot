require 'rails_helper'

RSpec.describe Plans::ExpireAccountFeatureOverridesJob do
  it 'removes expired overrides and restores the plan feature state' do
    plan = Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: ['automations'])
    account = create(:account, plan: plan)
    override = AccountFeatureOverride.create!(
      account: account, created_by: create(:user), feature_key: 'automations', enabled: false,
      reason: 'Expired', expires_at: 1.minute.ago
    )

    described_class.perform_now

    expect(AccountFeatureOverride.exists?(override.id)).to be(false)
    expect(account.reload).to be_feature_automations
  end
end
