require 'rails_helper'

RSpec.describe Captain::Pilot do
  let(:account) { create(:account) }

  it 'is disabled by default and for a missing account' do
    expect(described_class.enabled?(account)).to be false
    expect(described_class.enabled?(nil)).to be false
  end

  it 'reads the account pilot flag' do
    account.enable_features!('captain_pilot')

    expect(described_class.enabled?(account)).to be true
    expect(Plan::PLAN_FLAGS).not_to include('captain_pilot')
    expect(Plans::AccountFeatureSync::SYSTEM_FLAGS).to include('captain_pilot')
    expect(Plans::AccountFeatureSync::SYNCED_FLAGS).not_to include('captain_pilot')
  end
end
