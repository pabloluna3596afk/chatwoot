require 'rails_helper'

RSpec.describe 'plan feature rake tasks', type: :task do
  it 'keeps account flags unchanged during the default dry run and applies when requested' do
    plan = Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: ['automations'])
    account = create(:account, plan: plan)
    account.update!(feature_automations: false, feature_delayed_automations: false)
    task = Rake::Task['plans:sync_account_features']

    expect { with_modified_env('DRY_RUN' => nil) { task.invoke } }
      .to output(/account=#{account.id}.*automations/).to_stdout
    expect(account.reload).not_to be_feature_automations

    task.reenable
    with_modified_env('DRY_RUN' => 'false') { task.invoke }
    expect(account.reload).to be_feature_automations
  end

  it 'keeps plan keys unchanged during the default dry run' do
    plan = Plan.create!(name: 'Basic', slug: 'basico', feature_keys: ['captain_integration'])
    task = Rake::Task['plans:fill_feature_keys']

    expect { with_modified_env('DRY_RUN' => nil) { task.invoke } }.to output(/plan=basico/).to_stdout
    expect(plan.reload.feature_keys).to eq(['captain_integration'])
  end
end
