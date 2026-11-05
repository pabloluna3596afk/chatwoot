require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['plans:seed'] }

  before { task.reenable }

  it 'creates the current catalog and legacy plans with the expected visibility and limits' do
    expect { task.invoke }.to change(Plan, :count).by(8)

    expect(Plan.where(slug: %w[gratis basico inicio crecimiento]).order(:display_order).pluck(
             :price_monthly, :monthly_messages, :captain_copilot_responses, :captain_internal_calls,
             :max_documents, :storage_mb, :max_captain_assistants, :max_human_agents, :max_inboxes
           )).to eq([[0, 200, 0, 0, 0, 25, 1, 1, 1], [19, 500, 100, 100, 25, 250, 1, 2, 2],
                     [79, 1_000, 500, 500, 100, 100, 1, 2, 2], [149, 3_000, 1_500, 1_500, 250, 250, 3, 5, 5]])
    expect(Plan.where(slug: %w[negocio escala]).pluck(:is_active, :coming_soon)).to eq([[false, true], [false, true]])
    expect(Plan.where(slug: %w[prueba developer]).pluck(:is_active, :is_public)).to eq([[false, false], [false, false]])
    expect(Plan.find_by!(slug: 'gratis')).to have_attributes(is_default_trial: true, coming_soon: false)
    expect(Plan.find_by!(slug: 'developer').catalog_state).to eq('hidden')
  end

  it 'preserves every persisted attribute, assignment and usage on repeated runs' do
    plan = Plan.create!(name: 'Custom', slug: 'crecimiento', description: 'Private copy', monthly_messages: 123,
                        is_active: false, is_public: false, coming_soon: true, feature_keys: ['automations'])
    account = create(:account, plan: plan)
    account.current_usage_period
    original = plan.reload.attributes
    original_account = account.reload.attributes
    original_usage = account.account_plan_usages.reload.map(&:attributes)

    expect { task.invoke }.to change(Plan, :count).by(7)
    task.reenable
    expect { task.invoke }.not_to change(Plan, :count)

    expect(plan.reload.attributes).to eq(original)
    expect(account.reload.attributes).to eq(original_account)
    expect(account.account_plan_usages.reload.map(&:attributes)).to eq(original_usage)
  end

  it 'does not overwrite existing catalog values unless FORCE=1' do
    plan = Plan.create!(name: 'Crecimiento custom', slug: 'crecimiento', price_monthly: 123,
                        monthly_messages: 321, feature_keys: ['automations'])

    task.invoke
    expect(plan.reload).to have_attributes(price_monthly: 123, monthly_messages: 321, feature_keys: ['automations'])

    task.reenable
    ClimateControl.modify(FORCE: '1') { task.invoke }
    expect(plan.reload).to have_attributes(price_monthly: 149, monthly_messages: 3_000)
  end

  describe 'plans:fill_ai_bags' do
    subject(:fill_task) { described_class['plans:fill_ai_bags'] }

    before { fill_task.reenable }

    it 'previews NULL values without changing them' do
      plan = Plan.create!(name: 'Inicio', slug: 'inicio', captain_copilot_responses: nil, captain_internal_calls: nil)
      ClimateControl.modify(DRY_RUN: 'true') do
        expect { fill_task.invoke }.to output(/Would fill inicio/).to_stdout
      end
      expect(plan.reload).to have_attributes(captain_copilot_responses: nil, captain_internal_calls: nil)
    end

    it 'fills only NULL values and preserves edited limits on repeated runs' do
      plan = Plan.create!(name: 'Inicio', slug: 'inicio', captain_copilot_responses: 25, captain_internal_calls: nil)
      expect { fill_task.invoke }.to output(/Filled inicio/).to_stdout
      expect(plan.reload).to have_attributes(captain_copilot_responses: 25, captain_internal_calls: 500)
      fill_task.reenable
      expect { fill_task.invoke }.not_to output.to_stdout
    end
  end

  describe 'plans:limits_report' do
    subject(:report_task) { described_class['plans:limits_report'] }

    before { report_task.reenable }

    it 'prints every registered limit for each plan without changing plans' do
      plan = Plan.create!(name: 'Report', slug: 'report', limits: { 'max_flows' => 4 })
      original = plan.attributes

      expect { report_task.invoke }.to output(/Report \(report\).*max_flows: 4.*max_calendars: unlimited/m).to_stdout
      expect(plan.reload.attributes).to eq(original)
    end
  end
end
