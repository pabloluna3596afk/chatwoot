require 'rails_helper'

RSpec.describe Plans::AccountFeatureSync do
  let(:plan) { Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: %w[captain_integration automations]) }
  let(:account) { create(:account, plan: plan) }

  it 'syncs the assigned plan after account creation and plan changes' do
    expect(account).to be_feature_automations

    new_plan = Plan.create!(name: 'Basic plan', slug: 'basic-plan', feature_keys: ['captain_integration'])
    account.update!(plan: new_plan)

    expect(account.reload).not_to be_feature_automations
    expect(account).to be_feature_captain_integration
  end

  it 'applies plan features and turns off omitted plan flags on downgrade' do
    described_class.call(account)
    account.update!(plan: plan)
    expect(account.reload).to be_feature_automations
    expect(account).to be_feature_delayed_automations

    plan.update!(feature_keys: ['captain_integration'])
    described_class.call(account)
    expect(account.reload).not_to be_feature_automations
    expect(account).not_to be_feature_delayed_automations
  end

  it 'applies current on and off exceptions and leaves expired exceptions out' do
    user = create(:user)
    AccountFeatureOverride.create!(account: account, created_by: user, feature_key: 'automations', enabled: false,
                                   reason: 'test override')
    AccountFeatureOverride.create!(account: account, created_by: user, feature_key: 'campaigns', enabled: true,
                                   reason: 'expired', expires_at: 1.day.ago)

    described_class.call(account)
    expect(account.reload).not_to be_feature_automations
    expect(account).not_to be_feature_campaigns
  end

  it 'reports base and plan feature sources and allows an override to remove a base feature' do
    described_class.call(account)
    expect(account.feature_source('inbound_emails')).to eq(:base)
    expect(account.feature_source('automations')).to eq(:plan)

    AccountFeatureOverride.create!(account: account, created_by: create(:user), feature_key: 'inbound_emails',
                                   enabled: false, reason: 'Disabled by owner')
    account.reset_feature_override_cache!
    described_class.call(account)
    expect(account.feature_source('inbound_emails')).to eq(:override_off)
    expect(account.reload).not_to be_feature_inbound_emails
  end

  it 'preserves system and unclassified flags and is idempotent' do
    account.update!(feature_chatwoot_v4: false, feature_internal_tasks: true, feature_custom_roles: true)
    first = described_class.call(account)
    second = described_class.call(account)

    expect(account.reload).not_to be_feature_chatwoot_v4
    expect(account).to be_feature_internal_tasks
    expect(account).not_to be_feature_custom_roles
    expect(first).to be_present
    expect(second).to be_empty
  end

  it 'does nothing for accounts without a plan' do
    account.update!(plan: nil, feature_automations: true)
    expect(described_class.call(account)).to be_nil
    expect(account.reload).to be_feature_automations
  end

  it 'does not alter any flags for a plan without features and exposes a read-only preview' do
    plan.update!(feature_keys: [])
    account.update!(feature_captain_tasks: true)
    expect(Rails.logger).to receive(:warn).with(/plan has no features/)

    expect(described_class.preview(account)).to eq({})
    expect(described_class.call(account)).to be_nil
    expect(account.reload).to be_feature_captain_tasks
  end

  it 'previews the same account feature changes that call applies' do
    account.update!(feature_automations: false, feature_delayed_automations: false)
    changes = described_class.preview(account)

    expect(changes).to include('automations' => [false, true], 'delayed_automations' => [false, true])
    expect(described_class.call(account)).to eq(changes)
    expect(account.reload).to be_feature_automations
  end
end
