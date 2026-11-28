require 'rails_helper'

RSpec.describe 'Upstream 4.20 additive schema' do
  let(:connection) { ActiveRecord::Base.connection }

  it 'indexes only conversations with an SLA policy' do
    index = connection.indexes(:conversations).find { |candidate| candidate.name == 'index_conversations_on_sla_policy_id' }

    expect(index.columns).to eq(['sla_policy_id'])
    expect(index.where).to eq('(sla_policy_id IS NOT NULL)')
    expect(index).not_to be_unique
    expect(index).to be_valid
  end

  it 'indexes pending import items in import and item order' do
    index = connection.indexes(:data_import_items).find { |candidate| candidate.name == 'index_pending_data_import_items' }

    expect(index.columns).to eq(%w[data_import_id id])
    expect(index.where).to eq('(status = 0)')
    expect(index).not_to be_unique
    expect(index).to be_valid
  end

  it 'reserves export storage with required defaults, ownership and artifact expiry indexing' do
    columns = connection.columns(:data_exports).index_by(&:name)
    expect(columns.fetch('name').null).to be(false)
    expect(columns.fetch('account_id').null).to be(false)
    expect(columns.fetch('initiated_by_id').null).to be(true)
    expect(columns.fetch('data_type').default).to eq('contacts')
    expect(columns.fetch('status').default).to eq('0')
    expect(columns.fetch('processed_records').default).to eq('0')
    expect(columns.fetch('export_options').type).to eq(:jsonb)
    expect(columns.fetch('export_options').default).to eq('{}')
    %w[data_type status processed_records export_options].each do |name|
      expect(columns.fetch(name).null).to be(false)
    end

    foreign_keys = connection.foreign_keys(:data_exports)
    expect(foreign_keys.find { |key| key.column == 'account_id' }.to_table).to eq('accounts')
    initiator_key = foreign_keys.find { |key| key.column == 'initiated_by_id' }
    expect(initiator_key.to_table).to eq('users')
    expect(initiator_key.on_delete).to eq(:nullify)

    indexes = connection.indexes(:data_exports)
    expect(indexes.map(&:columns)).to include(['account_id'], ['initiated_by_id'], %w[account_id id])
    expiry_index = indexes.find { |index| index.name == 'index_data_exports_on_unexpired_completion' }
    expect(expiry_index.columns).to eq(['completed_at'])
    expect(expiry_index.where).to eq('(artifacts_expired_at IS NULL)')
    expect(indexes).to all(be_valid)
  end
end
