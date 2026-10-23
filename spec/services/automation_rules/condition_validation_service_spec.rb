require 'rails_helper'

RSpec.describe AutomationRules::ConditionValidationService do
  let(:probe_operators) { %w[equal_to contains unsupported] }

  let(:account) { create(:account) }
  let(:rule) { build(:automation_rule, account: account, event_name: 'message_created') }

  describe 'the shared save and evaluation contract' do
    let(:conversation) { create(:conversation, account: account) }

    it 'uses identical event attributes and operators in the model, validator and evaluator' do
      described_class::EVENTS.each do |event|
        rule.event_name = event
        rule.schedule = { kind: 'hours_since_last_incoming' } if rule.time_triggered?
        rule.conditions_attributes.each do |key|
          probe_operators.each do |operator|
            rule.conditions = [{ 'attribute_key' => key, 'filter_operator' => operator }]
            supported = described_class.new(rule).perform
            evaluator = AutomationRules::ConditionsFilterService.new(rule, conversation)

            expect(rule.valid?).to eq(supported), "model: #{event}/#{key}/#{operator}"
            expect(evaluator.rule_valid?).to eq(supported), "evaluator: #{event}/#{key}/#{operator}"
          end
        end
      end
      expect(rule.active).to be(true)
    end

    it 'uses the evaluator default custom attribute scope' do
      definition = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                                        attribute_display_type: 'text')
      rule.conditions = [{ 'attribute_key' => definition.attribute_key, 'filter_operator' => 'contains' }]

      expect(rule).to be_valid
      expect(AutomationRules::ConditionsFilterService.new(rule, conversation).rule_valid?).to be(true)
    end
  end

  describe '#perform' do
    context 'with standard attributes' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' },
          { 'values': ['+918484'], 'attribute_key': 'phone_number', 'query_operator': 'OR', 'filter_operator': 'contains' },
          { 'values': ['test'], 'attribute_key': 'email', 'query_operator': 'OR', 'filter_operator': 'contains' },
          { 'values': [true], 'attribute_key': 'private_note', 'query_operator': nil, 'filter_operator': 'equal_to' }
        ]
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with wrong attribute' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'not-a-standard-attribute-for-sure', 'query_operator': nil, 'filter_operator': 'equal_to' }
        ]
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with wrong filter operator' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'not-a-filter-operator' }
        ]
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with wrong query operator' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': 'invalid', 'filter_operator': 'attribute_changed' }
        ]
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with "attribute_changed" filter operator' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'attribute_changed' }
        ]
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with correct custom attribute' do
      before do
        create(:custom_attribute_definition,
               attribute_key: 'custom_attr_priority',
               account: account,
               attribute_model: 'conversation_attribute',
               attribute_display_type: 'list',
               attribute_values: %w[P0 P1 P2])

        rule.conditions = [
          {
            'values': ['true'],
            'attribute_key': 'custom_attr_priority',
            'filter_operator': 'equal_to',
            'custom_attribute_type': 'conversation_attribute'
          }
        ]
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with missing custom attribute' do
      before do
        rule.conditions = [
          {
            'values': ['true'],
            'attribute_key': 'attribute_is_not_present', # the attribute is not present
            'filter_operator': 'equal_to',
            'custom_attribute_type': 'conversation_attribute'
          }
        ]
      end

      it 'returns false for missing custom attribute' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end
  end
end
