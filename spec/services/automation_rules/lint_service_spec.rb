require 'rails_helper'

RSpec.describe AutomationRules::LintService do
  let(:account) { create(:account) }

  def build_rule(conditions:, actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }], **attrs)
    create(:automation_rule, account: account, conditions: conditions, actions: actions, **attrs)
  end

  def status_condition(values, operator: 'equal_to', joiner: nil)
    { 'attribute_key' => 'status', 'filter_operator' => operator, 'query_operator' => joiner, 'values' => values }
  end

  describe 'per-rule errors' do
    it 'flags AND-joined equal_to conditions on the same attribute with disjoint values' do
      rule = build_rule(conditions: [status_condition(['open'], joiner: 'AND'), status_condition(['resolved'])])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.ok?).to be(false)
      expect(result.errors.map(&:code)).to include('impossible_and')
    end

    it 'does not flag AND-joined conditions that share a value' do
      rule = build_rule(conditions: [status_condition(%w[open pending], joiner: 'AND'), status_condition(%w[open])])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).not_to include('impossible_and')
    end

    it 'does not flag conditions joined by OR' do
      rule = build_rule(conditions: [status_condition(['open'], joiner: 'OR'), status_condition(['resolved'])])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).not_to include('impossible_and')
    end

    it 'flags equal_to and not_equal_to on the same value' do
      rule = build_rule(conditions: [
        status_condition(['open'], joiner: 'AND'),
        status_condition(['open'], operator: 'not_equal_to')
      ])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).to include('impossible_and')
    end

    it 'flags an attribute that does not exist in the account' do
      rule = build_rule(conditions: [
        { 'attribute_key' => 'nope_not_real', 'filter_operator' => 'equal_to', 'query_operator' => nil, 'values' => ['x'] }
      ])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).to include('unknown_attribute_key')
    end

    it 'accepts a custom attribute defined on the account' do
      create(:custom_attribute_definition,
             account: account,
             attribute_key: 'plan_tier',
             attribute_model: 'conversation_attribute')
      rule = build_rule(conditions: [
        { 'attribute_key' => 'plan_tier', 'filter_operator' => 'equal_to', 'query_operator' => nil,
          'values' => ['gold'], 'custom_attribute_type' => 'conversation_attribute' }
      ])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).not_to include('unknown_attribute_key')
    end

    it 'flags a rule with no actions' do
      rule = build_rule(conditions: [status_condition(['open'])], actions: [])

      result = described_class.new(account: account, rules: [rule], subject: rule).perform

      expect(result.errors.map(&:code)).to include('empty_actions')
    end
  end

  describe 'cross-rule warnings' do
    let(:conditions) { [status_condition(['open'])] }

    def assign_team_rule(team_id, event_name: 'conversation_created', **attrs)
      build_rule(
        conditions: conditions,
        actions: [{ 'action_name' => 'assign_team', 'action_params' => [team_id] }],
        event_name: event_name,
        **attrs
      )
    end

    it 'warns when two rules on the same trigger assign different teams' do
      first = assign_team_rule(1)
      second = assign_team_rule(2)

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.warnings.map(&:code)).to include('conflicting_action_values')
    end

    it 'does not warn when both rules assign the same team' do
      first = assign_team_rule(1)
      second = assign_team_rule(1)

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.warnings.map(&:code)).not_to include('conflicting_action_values')
    end

    it 'warns when one rule resolves and another opens on the same trigger' do
      first = build_rule(conditions: conditions, event_name: 'conversation_updated',
                         actions: [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }])
      second = build_rule(conditions: conditions, event_name: 'conversation_updated',
                          actions: [{ 'action_name' => 'open_conversation', 'action_params' => [] }])

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.warnings.map(&:code)).to include('contradictory_actions')
    end

    it 'does not warn across different triggers' do
      first = assign_team_rule(1, event_name: 'conversation_created')
      second = assign_team_rule(2, event_name: 'conversation_updated')

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.warnings).to be_empty
    end

    it 'ignores inactive rules' do
      first = assign_team_rule(1, active: false)
      second = assign_team_rule(2)

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.warnings).to be_empty
    end

    it 'never blocks the save on a conflict' do
      first = assign_team_rule(1)
      second = assign_team_rule(2)

      result = described_class.new(account: account, rules: [first, second], subject: second).perform

      expect(result.ok?).to be(true)
      expect(result.warnings).not_to be_empty
    end

    # A rule being created is not yet in the account's rules and has no id, so
    # pairing by id skipped it entirely and the conflict went unreported.
    it 'warns on a rule that is not saved yet and absent from the rule list' do
      existing = create(:automation_rule, account: account, event_name: 'conversation_created',
                                          conditions: conditions,
                                          actions: [{ 'action_name' => 'open_conversation', 'action_params' => [] }])
      subject_rule = build_rule(conditions: conditions,
                                actions: [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }])

      result = described_class.new(account: account, rules: [existing], subject: subject_rule).perform

      expect(result.warnings.map(&:code)).to include('contradictory_actions')
    end

    # Two unsaved rules both answer `nil` to `id`, which made them look like the
    # same rule and paired unrelated drafts against each other.
    it 'does not pair two unsaved rules that are not the subject' do
      first = build_rule(conditions: conditions,
                         actions: [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }])
      second = build_rule(conditions: conditions,
                          actions: [{ 'action_name' => 'open_conversation', 'action_params' => [] }])
      subject_rule = build_rule(conditions: conditions,
                                actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }])

      result = described_class.new(account: account, rules: [first, second], subject: subject_rule).perform

      expect(result.warnings).to be_empty
    end

    it 'compares the edited version of a rule, not the one still in the database' do
      stored = create(:automation_rule, account: account, event_name: 'conversation_created',
                                        conditions: conditions,
                                        actions: [{ 'action_name' => 'open_conversation', 'action_params' => [] }])
      other = create(:automation_rule, account: account, event_name: 'conversation_created',
                                       conditions: conditions,
                                       actions: [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }])
      edited = AutomationRule.find(stored.id)
      edited.actions = [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }]

      result = described_class.new(account: account, rules: [stored, other], subject: edited).perform

      expect(result.warnings).to be_empty
    end
  end
end
