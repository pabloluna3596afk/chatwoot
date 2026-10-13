require 'rails_helper'

RSpec.describe Calendar::AppointmentAttributes::Provisioner do
  subject(:provisioner) { described_class.new(account: account) }

  let(:account) { create(:account, locale: 'es') }
  let(:keys) { Calendar::AppointmentAttributes::Definitions::TYPES.keys }

  it 'starts unconfigured without creating definitions' do
    expect(provisioner.status).to include('keys' => nil, 'enabled_keys' => [], 'results' => {})
  end

  it 'creates the four contact attributes with the approved types and category' do
    result = provisioner.perform(keys: keys)
    definitions = account.custom_attribute_definitions.contact_attribute.order(:attribute_key)

    expect(definitions.pluck(:attribute_key, :attribute_display_type).to_h).to eq(Calendar::AppointmentAttributes::Definitions::TYPES)
    expect(definitions.pluck(:category).uniq).to eq(['Citas'])
    expect(definitions.find_by!(attribute_key: 'ultima_cita').attribute_display_name).to eq('Última cita')
    expect(result['results'].values.pluck('status')).to eq(Array.new(4, 'created'))
    expect(account.reload.appointment_attributes['enabled_keys']).to eq(keys)
  end

  it 'reuses the same key and type without changing its metadata' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                                      attribute_key: 'ultima_cita', attribute_display_type: :datetime,
                                                      attribute_display_name: 'My date', category: 'Existing')

    expect { provisioner.perform(keys: ['ultima_cita']) }.not_to change(CustomAttributeDefinition, :count)
    expect(provisioner.status['results']['ultima_cita']['status']).to eq('reused')
    expect(definition.reload).to have_attributes(attribute_display_name: 'My date', category: 'Existing')
  end

  it 'reports an incompatible type and does not activate or change it' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                                      attribute_key: 'ultima_cita', attribute_display_type: :text, category: 'Existing')
    original = definition.attributes
    result = provisioner.perform(keys: %w[ultima_cita total_citas])

    expect(result['results']['ultima_cita']).to eq('status' => 'conflict', 'expected_type' => 'datetime', 'actual_type' => 'text')
    expect(result['enabled_keys']).to eq(['total_citas'])
    expect(definition.reload.attributes).to eq(original)
  end

  it 'keeps conversation definitions separate from contact definitions' do
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'ultima_cita')

    expect(provisioner.perform(keys: ['ultima_cita'])['results']['ultima_cita']['status']).to eq('created')
  end

  it 'enqueues one backfill on activation and remains idempotent on repeated saves' do
    expect { provisioner.perform(keys: keys) }.to have_enqueued_job(Calendar::AppointmentAttributes::BackfillJob).with(account.id)
    expect { provisioner.perform(keys: keys) }.not_to have_enqueued_job(Calendar::AppointmentAttributes::BackfillJob)
    expect(account.custom_attribute_definitions.contact_attribute.count).to eq(4)
  end

  it 'does not enqueue backfill for conflicts only' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_key: 'ultima_cita', attribute_display_type: :text)

    expect { provisioner.perform(keys: ['ultima_cita']) }.not_to have_enqueued_job(Calendar::AppointmentAttributes::BackfillJob)
  end

  it 'backfills an active attribute when its deleted definition is recreated' do
    provisioner.perform(keys: ['total_citas'])
    account.custom_attribute_definitions.find_by!(attribute_key: 'total_citas').destroy!

    expect { provisioner.perform(keys: ['total_citas']) }.to have_enqueued_job(Calendar::AppointmentAttributes::BackfillJob).with(account.id)
  end

  it 'preserves definitions and values when disabling and backfills when reactivating' do
    provisioner.perform(keys: keys)
    contact = create(:contact, account: account, custom_attributes: { 'total_citas' => 3 })

    expect { provisioner.perform(keys: []) }.not_to change(CustomAttributeDefinition, :count)
    expect(account.reload.appointment_attributes['enabled_keys']).to be_empty
    expect(contact.reload.custom_attributes).to eq('total_citas' => 3)
    expect { provisioner.perform(keys: keys) }.to have_enqueued_job(Calendar::AppointmentAttributes::BackfillJob).with(account.id)
  end
end
