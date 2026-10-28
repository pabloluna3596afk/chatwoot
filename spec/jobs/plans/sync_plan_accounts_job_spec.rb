require 'rails_helper'

RSpec.describe Plans::SyncPlanAccountsJob do
  it 'synchronizes all accounts assigned to the changed plan' do
    plan = Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: ['automations'])
    accounts = create_list(:account, 2, plan: plan, feature_automations: false, feature_delayed_automations: false)

    described_class.perform_now(plan.id)

    expect(accounts.map { |account| account.reload.feature_automations? }).to eq([true, true])
    expect(accounts.map { |account| account.reload.feature_delayed_automations? }).to eq([true, true])
  end

  it 'skips accounts when the plan has no feature catalog' do
    plan = Plan.create!(name: 'Unfilled', slug: 'unfilled', feature_keys: [])
    account = create(:account, plan: plan, feature_automations: true)
    expect(Rails.logger).to receive(:warn).with(/plan has no features/)

    described_class.perform_now(plan.id)

    expect(account.reload).to be_feature_automations
  end
end
