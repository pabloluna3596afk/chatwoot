require 'rails_helper'
require Rails.root.join('db/migrate/20261109120000_include_customer_data_export_in_paid_plans')

RSpec.describe IncludeCustomerDataExportInPaidPlans, type: :model do
  let(:migration) { described_class.new }
  let!(:paid) { Plan.create!(name: 'Paid', slug: 'paid', price_monthly: 19, feature_keys: ['automations']) }
  let!(:free) { Plan.create!(name: 'Free', slug: 'free', feature_keys: ['captain_integration']) }
  let!(:trial) { Plan.create!(name: 'Trial', slug: 'trial', price_monthly: 19, is_default_trial: true) }

  it 'backfills only paid non-trial plans, preserves features, and is idempotent and reversible' do
    account = create(:account, plan: paid)
    2.times { migration.migrate(:up) }
    expect(paid.reload.feature_keys).to eq(%w[automations customer_data_export])
    expect(free.reload.feature_keys).to eq(['captain_integration'])
    expect(trial.reload.feature_keys).to eq([])
    expect(account.reload).not_to be_feature_customer_data_export

    sync_task = Rake::Task['plans:sync_features']
    sync_task.reenable
    Rake::Task['plans:sync_account_features'].reenable
    ClimateControl.modify(DRY_RUN: 'false') { sync_task.invoke }
    expect(account.reload).to be_feature_customer_data_export

    2.times { migration.migrate(:down) }
    expect(paid.reload.feature_keys).to eq(['automations'])
    expect(free.reload.feature_keys).to eq(['captain_integration'])
    expect(trial.reload.feature_keys).to eq([])
  end
end
