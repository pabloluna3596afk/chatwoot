require 'rails_helper'

RSpec.describe AutomationRules::SimulationService do
  subject(:simulation) { described_class.new(account: account, conversation: conversation, event_name: event_name) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, status: :open) }
  let(:event_name) { 'conversation_created' }
  let(:condition) do
    { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }
  end
  let!(:rule) do
    create(:automation_rule, account: account, event_name: event_name, conditions: [condition],
                             actions: [{ 'action_name' => 'send_message', 'action_params' => ['Hello'] }])
  end

  describe '#perform' do
    it 'preserves the runtime matches and action descriptions for valid rules' do
      expect(AutomationRules::ConditionsFilterService.new(rule, conversation).perform).to be(true)

      result = simulation.perform
      expected_match = { rule_id: rule.id, rule_name: rule.name, order: 1,
                         actions: [{ action_name: 'send_message', action_params: ['Hello'] }] }

      expect(result.matches.map(&:to_h)).to eq([expected_match])
      expect(result.evaluated_count).to eq(1)
      expect(result.diagnostics).to be_empty
    end

    it 'does not match valid conditions that the conversation does not satisfy' do
      conversation.update!(status: :resolved)

      expect(simulation.perform.matches).to be_empty
    end

    context 'with an invalid condition' do
      before do
        # Persist an invalid legacy configuration without running callbacks.
        rule.update_columns(conditions: [condition.merge('filter_operator' => 'unsupported')])
      end

      it 'leaves persisted data, counters, reauthorization state and queues unchanged across two simulations' do
        conversation
        attributes = rule.reload.attributes
        conversation_attributes = conversation.reload.attributes
        counters = [rule.authorization_error_count, rule.reauthorization_required?]
        jobs = enqueued_jobs.dup
        mail = ActionMailer::Base.deliveries.dup
        message_count = conversation.messages.count

        2.times { simulation.perform }

        expect(rule.reload.attributes).to eq(attributes)
        expect(conversation.reload.attributes).to eq(conversation_attributes)
        expect([rule.authorization_error_count, rule.reauthorization_required?]).to eq(counters)
        expect(enqueued_jobs).to eq(jobs)
        expect(ActionMailer::Base.deliveries).to eq(mail)
        expect(conversation.messages.count).to eq(message_count)
      end

      it 'returns the offending condition and a readable diagnostic without raising' do
        result = simulation.perform
        diagnostic = { rule_id: rule.id, rule_name: rule.name, condition_index: 0,
                       attribute_key: 'status', filter_operator: 'unsupported',
                       message: 'The filter operator is not supported for this attribute.' }

        expect(result.matches).to be_empty
        expect(result.evaluated_count).to eq(1)
        expect(result.diagnostics).to eq([diagnostic])
      end

      it 'continues evaluating other valid rules' do
        valid_rule = create(:automation_rule, account: account, event_name: event_name, conditions: [condition])

        expect(simulation.perform.matches.map(&:rule_id)).to eq([valid_rule.id])
      end

      it 'identifies the position of an invalid condition after a valid condition' do
        rule.update_columns(conditions: [condition.merge('query_operator' => 'AND'),
                                         condition.merge('filter_operator' => 'unsupported')])

        expect(simulation.perform.diagnostics.first).to include(condition_index: 1, filter_operator: 'unsupported')
      end
    end

    context 'with a deleted custom attribute' do
      before do
        rule.update_columns(conditions: [condition.merge('attribute_key' => 'deleted_attribute')])
      end

      it 'identifies the unavailable attribute without modifying the rule' do
        expect(simulation.perform.diagnostics.first).to include(attribute_key: 'deleted_attribute', condition_index: 0)
        expect(rule.reload.active).to be(true)
      end
    end

    context 'with an invalid query operator' do
      before do
        rule.update_columns(conditions: [condition.merge('query_operator' => 'XOR')])
      end

      it 'explains the allowed query operators' do
        expect(simulation.perform.diagnostics.first[:message]).to eq('The query operator must be AND or OR.')
      end
    end

    context 'with a message event' do
      let(:event_name) { 'message_created' }
      let(:condition) do
        { 'attribute_key' => 'content', 'filter_operator' => 'contains', 'values' => ['latest'], 'query_operator' => nil }
      end

      it 'uses the latest message as the runtime message context' do
        create(:message, conversation: conversation, account: account, content: 'older')
        message = create(:message, conversation: conversation, account: account, content: 'latest')

        expect(AutomationRules::ConditionsFilterService.new(rule, conversation, message: message).perform).to be(true)
        expect(simulation.perform.matches.map(&:rule_id)).to eq([rule.id])
      end
    end
  end
end
