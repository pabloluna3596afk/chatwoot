require 'rails_helper'

RSpec.describe Variables::Writer do
  let(:account) { create(:account, appointment_attributes: { 'enabled_keys' => ['total_citas'] }) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'total_citas' => 3, 'legacy' => 'keep' }) }
  let(:writer) { described_class.new(account: account) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'total_citas', attribute_display_type: 'number')
  end

  it 'MV-14: rejects writes and deletion of Calendar derivatives' do
    expect(writer.target('contact.custom_attribute.total_citas', context: 'automation')).to be_nil
    expect(writer.target('contact.custom_attribute.total_citas', context: 'whatsapp_flow')).to be_nil
    expect { writer.patch(scope: 'contact', values: { 'total_citas' => 7 }) }.to raise_error(ActionController::ParameterMissing)
    expect { writer.remove(scope: 'contact', current: contact.custom_attributes, keys: ['total_citas']) }
      .to raise_error(ActionController::ParameterMissing)
    expect { writer.patch(scope: 'contact', current: contact.custom_attributes, values: {}, replace: true) }
      .to raise_error(ActionController::ParameterMissing)
  end

  it 'keeps managed values on a partial update and preserves legacy JSON keys' do
    expect(writer.patch(scope: 'contact', current: contact.custom_attributes, values: { 'legacy' => 'updated' }))
      .to eq('total_citas' => 3, 'legacy' => 'updated')
  end

  it 'rejects malformed JSON rather than coercing it' do
    [nil, [], 'value', true].each do |value|
      expect { writer.patch(scope: 'contact', values: value) }.to raise_error(ActionController::ParameterMissing)
    end
  end

  it 'uses exact keys and the same eligibility as Flow capture' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'level.vip', attribute_display_type: 'text')
    attributes = writer.attributes(record: contact, target: 'contact.custom_attribute.level.vip', value: 'VIP', context: 'whatsapp_flow')
    expect(attributes[:custom_attributes]).to include('level.vip' => 'VIP', 'total_citas' => 3)
    expect(Whatsapp::Flows::SaveTargets.compatible?({ 'type' => 'short_text' }, 'contact.custom_attribute.total_citas', account)).to be(false)
  end

  it 'protects formulas in every scope' do
    %w[contact conversation company].each do |scope|
      create(:custom_attribute_definition, account: account, attribute_model: "#{scope}_attribute", attribute_key: 'computed',
                                           formula: { 'op' => 'count', 'source_attribute_key' => 'amount' })
      expect { described_class.new(account: account).patch(scope: scope, values: { 'computed' => 5 }) }
        .to raise_error(ActionController::ParameterMissing)
    end
  end
end
