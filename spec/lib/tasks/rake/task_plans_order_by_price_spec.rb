require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['plans:order_by_price'] }

  before do
    task.reenable
    Plan.create!(name: 'Caro', slug: 'caro', price_monthly: 299, display_order: 0)
    Plan.create!(name: 'Barato', slug: 'barato', price_monthly: 49, display_order: 5)
    Plan.create!(name: 'Medio', slug: 'medio', price_monthly: 119, display_order: 2)
  end

  it 'does not change anything by default' do
    expect { task.invoke }.not_to(change { Plan.order(:id).pluck(:display_order) })
  end

  it 'renumbers display_order by monthly price when DRY_RUN=false' do
    ClimateControl.modify(DRY_RUN: 'false') { task.invoke }

    expect(Plan.order(:display_order).pluck(:slug)).to eq(%w[barato medio caro])
    expect(Plan.order(:display_order).pluck(:display_order)).to eq([0, 1, 2])
  end
end
