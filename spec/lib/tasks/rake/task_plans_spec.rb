require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['plans:seed'] }

  before { task.reenable }

  it 'creates missing plans with safe catalog visibility' do
    expect { task.invoke }.to change(Plan, :count).by(6)

    expect(Plan.find_by!(slug: 'prueba')).to have_attributes(coming_soon: false, is_public: true)
    expect(Plan.where(slug: %w[inicio crecimiento negocio escala]).pluck(:coming_soon)).to eq([true] * 4)
    expect(Plan.find_by!(slug: 'developer').catalog_state).to eq('hidden')
    expect(Plan.where(slug: %w[prueba inicio crecimiento negocio escala]).order(:display_order).pluck(
             :captain_copilot_responses, :captain_internal_calls
           )).to eq([[0, 0], [500, 500], [1_500, 1_500], [4_000, 4_000], [10_000, 10_000]])
    expect(Plan.find_by!(slug: 'developer')).to have_attributes(captain_copilot_responses: nil, captain_internal_calls: nil)
  end

  it 'preserves every persisted attribute, assignment and usage on repeated runs' do
    plan = Plan.create!(name: 'Custom', slug: 'crecimiento', description: 'Private copy', monthly_messages: 123,
                        is_active: false, is_public: false, coming_soon: true, feature_keys: ['automations'])
    account = create(:account, plan: plan)
    account.current_usage_period
    original = plan.reload.attributes
    original_account = account.reload.attributes
    original_usage = account.account_plan_usages.reload.map(&:attributes)

    expect { task.invoke }.to change(Plan, :count).by(5)
    task.reenable
    expect { task.invoke }.not_to change(Plan, :count)

    expect(plan.reload.attributes).to eq(original)
    expect(account.reload.attributes).to eq(original_account)
    expect(account.account_plan_usages.reload.map(&:attributes)).to eq(original_usage)
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
