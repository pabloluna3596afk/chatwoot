require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['plans:seed'] }

  before { task.reenable }

  it 'creates missing plans with safe catalog visibility' do
    expect { task.invoke }.to change(Plan, :count).by(6)

    expect(Plan.find_by!(slug: 'prueba')).to have_attributes(coming_soon: false, is_public: true)
    expect(Plan.where(slug: %w[inicio crecimiento negocio escala]).pluck(:coming_soon)).to eq([true] * 4)
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

    expect { task.invoke }.to change(Plan, :count).by(5)
    task.reenable
    expect { task.invoke }.not_to change(Plan, :count)

    expect(plan.reload.attributes).to eq(original)
    expect(account.reload.attributes).to eq(original_account)
    expect(account.account_plan_usages.reload.map(&:attributes)).to eq(original_usage)
  end
end
