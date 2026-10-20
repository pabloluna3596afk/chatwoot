require 'rails_helper'

RSpec.describe Variables::Catalog do
  let(:account) { create(:account) }
  let(:catalog) { described_class.new(account: account, surface: 'message').as_json }

  it 'keeps every definition identity and literal key, including reserved aliases and punctuation' do
    definitions = %w[documento MARÍA nivel-vip nivel.vip conversacion_tier].map do |key|
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: key)
    end
    conversation = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute', attribute_key: 'tier')
    entries = catalog[:variables].select { |entry| entry[:reference][:kind] == 'custom_attribute' }

    expect(entries.map { |entry| entry[:reference][:definitionId] }).to match_array(definitions.map(&:id) + [conversation.id])
    expect(entries.map { |entry| entry[:expression] }).to include("{{ contact.custom_attribute['nivel.vip'] }}",
                                                                  "{{ contact.custom_attribute['MARÍA'] }}")
    expect(entries.find { |entry| entry[:key] == 'documento' }[:aliases]).to be_empty
    aliases = catalog[:variables].flat_map { |entry| entry[:aliases] }
    expect(aliases.uniq).to eq(aliases)
  end

  it 'separates company and Flow groups and declares unavailable contexts' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: 'company_attribute', attribute_key: 'tier')
    company = catalog[:variables].find { |entry| entry[:reference][:definitionId] == definition.id }
    flow = catalog[:variables].find { |entry| entry[:id] == 'flow.variables' }

    expect(company).to include(group: 'company', requiresContext: ['company'], available: false)
    expect(flow).to include(group: 'flow', requiresContext: ['flow'], available: false)
  end

  it 'marks enabled Calendar derivatives and formulas as managed without changing unowned attributes' do
    account.update!(appointment_attributes: { 'enabled_keys' => ['total_citas'] })
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'total_citas',
                                         attribute_display_type: 'number')
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'ultima_cita',
                                         attribute_display_type: 'datetime')
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'total',
                                         formula: { 'op' => 'count', 'source_attribute_key' => 'amount', 'source_model' => 'conversation' })
    entries = catalog[:variables].index_by { |entry| entry[:key] }

    expect(entries['total_citas']).to include(managedBy: 'calendar', writable: false, writeContexts: [])
    expect(entries['ultima_cita']).to include(managedBy: nil, writable: true)
    expect(entries['total']).to include(managedBy: 'formula', writable: false)
  end

  it 'changes the definitions version after edits, deletion and Calendar ownership changes' do
    definition = create(:custom_attribute_definition, account: account, attribute_key: 'tier')
    initial = described_class.new(account: account, surface: 'message').as_json[:definitionsVersion]
    definition.update!(attribute_display_name: 'Changed')
    edited = described_class.new(account: account, surface: 'message').as_json[:definitionsVersion]
    definition.destroy!
    deleted = described_class.new(account: account, surface: 'message').as_json[:definitionsVersion]

    expect([initial, edited, deleted].uniq.size).to eq(3)
  end

  it 'does not offer conversation or dates as available in the current campaign contract' do
    entries = described_class.new(account: account, surface: 'campaign').as_json[:variables].index_by { |entry| entry[:id] }

    expect(entries['conversation.id'][:available]).to be(false)
    expect(entries['date.today'][:available]).to be(false)
    expect(entries['contact.document_number'][:aliases]).to eq(['documento'])
    expect(catalog[:schemaVersion]).to eq(1)
  end
end
