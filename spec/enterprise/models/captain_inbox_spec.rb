require 'rails_helper'

RSpec.describe CaptainInbox do
  let(:connection) { build(:captain_inbox) }
  let(:leaf) { { 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['example.com'] } }

  it 'defaults new connections to inherit without custom rules' do
    expect(connection).to have_attributes(audience_mode: 'inherit', audience_rules: {})
  end

  %w[inherit everyone custom].each do |mode|
    it "accepts #{mode} mode" do
      connection.audience_mode = mode

      expect(connection).to be_valid
    end
  end

  [nil, '', 'unknown'].each do |mode|
    it "rejects invalid mode #{mode.inspect}" do
      connection.audience_mode = mode

      expect(connection).not_to be_valid
      expect(connection.errors[:audience_mode]).to be_present
    end
  end

  it 'validates the tree using the assistant account custom attributes' do
    create(:custom_attribute_definition, account: connection.captain_assistant.account,
                                         attribute_model: :contact_attribute, attribute_key: 'tier', attribute_display_type: :text)
    connection.audience_rules = { tree: { operator: 'and', conditions: [leaf.merge('attribute_key' => 'tier')] } }

    expect(connection).to be_valid
  end

  it 'accepts all supported rule types together' do
    connection.audience_rules = {
      tree: { operator: 'and', conditions: [leaf] }, contact_scope: 'returning',
      phones: { mode: 'allow', list: ['0991234567'] }, channel_ids: { mode: 'deny', list: ['user'] },
      emails: { mode: 'allow', list: ['@example.com'] }
    }

    expect(connection).to be_valid
  end

  it 'accepts the maximum list length and entry length' do
    connection.audience_rules = { channel_ids: { mode: 'allow', list: Array.new(1000) { 'a' * 120 } } }

    expect(connection).to be_valid
  end

  [
    nil, [], 'rules', { 'unknown' => true }, { 'on_missing_data' => 'reply' }, { 'contact_scope' => 'existing' },
    { 'tree' => nil }, { 'tree' => {} }, { 'tree' => { 'operator' => 'and', 'conditions' => [] } },
    { 'phones' => nil }, { 'phones' => [] }, { 'phones' => { 'mode' => 'both', 'list' => ['1'] } },
    { 'phones' => { 'mode' => 'allow', 'list' => '1' } },
    { 'phones' => { 'mode' => 'allow', 'list' => [123] } },
    { 'phones' => { 'mode' => 'allow', 'list' => [''] } },
    { 'phones' => { 'mode' => 'allow', 'list' => ['a' * 121] } },
    { 'phones' => { 'mode' => 'allow', 'list' => Array.new(1001, '1') } },
    { 'phones' => { 'mode' => 'allow', 'list' => ['1'], 'extra' => true } }
  ].each_with_index do |rules, index|
    it "rejects malformed rules #{index + 1} even outside custom mode" do
      connection.audience_rules = rules

      expect(connection).not_to be_valid
      expect(connection.errors[:audience_rules]).to be_present
    end
  end

  it 'rejects unknown tree group keys' do
    connection.audience_rules = { tree: { operator: 'and', conditions: [leaf], extra: true } }

    expect(connection).not_to be_valid
  end

  it 'rejects unknown nested tree leaf keys' do
    connection.audience_rules = { tree: { operator: 'and', conditions: [leaf.merge('extra' => true)] } }

    expect(connection).not_to be_valid
  end

  it 'rejects object values that strong parameters would silently drop' do
    connection.audience_rules = { tree: leaf.merge('values' => [{ 'nested' => 'value' }]) }

    expect(connection).not_to be_valid
  end

  it 'rejects unsupported operators and excessive tree depth' do
    tree = leaf.merge('filter_operator' => 'unsupported')
    connection.audience_rules = { tree: tree }
    expect(connection).not_to be_valid

    tree = leaf
    3.times { tree = { 'operator' => 'and', 'conditions' => [tree] } }
    connection.audience_rules = { tree: tree }
    expect(connection).not_to be_valid
  end
end
