require 'rails_helper'

RSpec.describe Plans::PublicSerializer do
  let(:plan) do
    Plan.new(name: 'Catalog', slug: 'catalog', is_recommended: true,
             addon_agent_price: 12.5, addon_bot_price: 0, credit_unit_price: -1)
  end

  it 'serializes the recommended flag and only positive add-on prices' do
    expect(described_class.new(plan).as_json).to include(
      recommended: true,
      addon_agent_price: 12.5,
      addon_bot_price: nil,
      credit_unit_price: nil
    )
  end

  it 'exposes the customer download label from the public catalog' do
    plan.feature_keys = ['customer_data_export']
    expect(described_class.new(plan).as_json[:features]).to include(
      key: 'customer_data_export', label: 'Descarga de datos de clientes'
    )
  end
end
