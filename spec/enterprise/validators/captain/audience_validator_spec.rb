require 'rails_helper'

RSpec.describe Captain::AudienceValidator do
  subject(:validator) { described_class.new }

  let(:account) { create(:account) }
  let(:leaf) { { 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['@example.com'] } }

  it 'accepts a valid condition tree' do
    expect(validator.valid_tree?({ 'operator' => 'and', 'conditions' => [leaf] }, account)).to be true
  end

  it 'rejects invalid operators and values' do
    expect(validator.valid_tree?(leaf.merge('filter_operator' => 'execute'), account)).to be false
    expect(validator.valid_tree?(leaf.merge('values' => []), account)).to be false
    expect(validator.valid_tree?('invalid', account)).to be false
  end

  it 'accepts a custom attribute only for the account defining it' do
    create(:custom_attribute_definition, account: account, attribute_key: 'eval_tier', attribute_model: :contact_attribute,
                                         attribute_display_type: :text)
    custom_leaf = leaf.merge('attribute_key' => 'eval_tier')
    expect(validator.valid_tree?(custom_leaf, account)).to be true
    expect(validator.valid_tree?(custom_leaf, create(:account))).to be false
  end
end
