require 'rails_helper'

RSpec.describe Whatsapp::Flows::DefinitionValidator do
  let(:account) { create(:account) }
  let(:flow) { build(:whatsapp_flow, account: account) }
  let(:block) { flow.definition['screens'].first['blocks'].first }

  it 'accepts writable Liquid targets without changing the Meta export' do
    original = flow.flow_json
    block['save_to'] = { 'target' => 'contact.email' }
    expect(flow.definition_check).to be_valid
    expect(flow.flow_json).to eq(original)
  end

  it 'rejects derived, unknown, conversation and file destinations and malformed mappings' do
    %w[contact.first_name contact.country_code agent.name conversation.id contact.unknown].each do |target|
      block['save_to'] = { 'target' => target }
      expect(flow.definition_check.errors.pluck(:code)).to include('save_to_incompatible')
    end
    block['save_to'] = 'contact.email'
    expect(flow.definition_check.errors.pluck(:code)).to include('save_to_invalid')
    block.merge!('type' => 'photo', 'save_to' => { 'target' => 'contact.name' })
    expect(flow.definition_check.errors.pluck(:code)).to include('save_to_incompatible')
  end

  it 'rejects two fields saving to the same destination' do
    block['save_to'] = { 'target' => 'contact.name' }
    flow.definition['screens'].first['blocks'] << block.merge('key' => 'other')
    expect(flow.definition_check.errors.pluck(:code)).to include('save_to_duplicate')
  end

  it 'checks account, attribute model, computed fields and type compatibility' do
    attribute = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                                     attribute_display_type: :date, attribute_key: 'birthday')
    block['save_to'] = { 'target' => 'contact.custom_attribute.birthday' }
    expect(flow.definition_check).not_to be_valid
    block['type'] = 'date'
    expect(flow.definition_check).to be_valid
    expect(described_class.new(flow.definition, account: create(:account)).call).not_to be_valid
    attribute.update!(attribute_model: :conversation_attribute)
    expect(flow.definition_check).not_to be_valid
  end

  it 'allows multi-checkbox only for text and optin only for boolean attributes' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_display_type: :checkbox, attribute_key: 'accept')
    block.merge!('type' => 'optin', 'save_to' => { 'target' => 'contact.custom_attribute.accept' })
    expect(flow.definition_check).to be_valid
    block['type'] = 'checkbox'
    block['options'] = [{ 'id' => 'one', 'title' => 'One' }]
    expect(flow.definition_check).not_to be_valid
    block['save_to'] = { 'target' => 'contact.name' }
    expect(flow.definition_check).to be_valid
  end
end
