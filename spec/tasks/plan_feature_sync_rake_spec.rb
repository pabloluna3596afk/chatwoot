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

  it 'fills the corrected tier matrix with captain tasks starting at Basic' do
    free = Plan.create!(name: 'Free', slug: 'gratis')
    trial = Plan.create!(name: 'Trial', slug: 'prueba')
    basic = Plan.create!(name: 'Basic', slug: 'basico')
    task = Rake::Task['plans:fill_feature_keys']

    task.reenable
    with_modified_env('DRY_RUN' => 'false') { task.invoke }

    expect(free.reload.feature_keys).not_to include('captain_tasks')
    expect(trial.reload.feature_keys).not_to include('captain_tasks')
    expect(basic.reload.feature_keys).to include('captain_tasks')
  end

  it 'skips syncing accounts whose plan feature catalog is empty' do
    plan = Plan.create!(name: 'Unfilled', slug: 'unfilled-task', feature_keys: [])
    account = create(:account, plan: plan, feature_automations: true)
    task = Rake::Task['plans:sync_account_features']
    task.reenable

    expect { with_modified_env('DRY_RUN' => 'false') { task.invoke } }
      .to output(/SALTADA: plan sin features account=#{account.id}/).to_stdout
    expect(account.reload).to be_feature_automations
  end

  it 'migrates legacy copilot feature keys idempotently' do
    plan = Plan.create!(name: 'Legacy', slug: 'legacy-copilot')
    # Seed the invalid legacy payload that model validation correctly rejects.
    plan.update_column(:feature_keys, ['copilot']) # rubocop:disable Rails/SkipsModelValidations
    task = Rake::Task['plans:migrate_copilot_feature_keys']

    expect { with_modified_env('DRY_RUN' => 'false') { task.invoke } }
      .to output(/captain_tasks/).to_stdout
    expect(plan.reload.feature_keys).to eq(['captain_tasks'])

    task.reenable
    expect { with_modified_env('DRY_RUN' => 'false') { task.invoke } }.not_to output.to_stdout
  end
end
