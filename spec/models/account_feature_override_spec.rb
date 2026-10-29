require 'rails_helper'

RSpec.describe AccountFeatureOverride do
  let(:plan) { Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: ['captain_integration']) }
  let(:account) { create(:account, plan: plan) }
  let(:user) { create(:user) }
  let(:attributes) do
    { account: account, created_by: user, feature_key: 'automations', enabled: true, reason: 'Approved exception' }
  end

  it 'requires a known catalog key, reason and unique account/key pair' do
    override = described_class.new(attributes)
    expect(override).to be_valid

    override.save!
    duplicate = described_class.new(attributes)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:feature_key]).to be_present

    invalid = described_class.new(attributes.merge(feature_key: 'unknown', reason: ''))
    expect(invalid).not_to be_valid
  end

  it 'returns the account feature to its plan when deleted' do
    override = described_class.create!(attributes)
    expect(account.reload.feature_automations?).to be(true)

    override.destroy!
    expect(account.reload.feature_automations?).to be(false)
  end

  it 'allows a per-account override of a base feature' do
    override = described_class.create!(attributes.merge(feature_key: 'inbound_emails', enabled: false))
    Plans::AccountFeatureSync.call(account)

    expect(account.reload).not_to be_feature_inbound_emails
    expect(account.feature_source('inbound_emails')).to eq(:override_off)

    override.destroy!
    account.reset_feature_override_cache!
    Plans::AccountFeatureSync.call(account)
    expect(account.reload).to be_feature_inbound_emails
    expect(account.feature_source('inbound_emails')).to eq(:base)
  end
end
