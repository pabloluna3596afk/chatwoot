# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AutomationRule do
  let!(:automation_rule) { create(:automation_rule, name: 'automation rule 1') }

  describe 'the automation contract' do
    it 'accepts the Enterprise SLA action with its required parameters' do
      automation_rule.actions = [{ action_name: 'add_sla', action_params: [12] }]

      expect(automation_rule).to be_valid
    end

    it 'rejects missing SLA parameters' do
      automation_rule.actions = [{ action_name: 'add_sla', action_params: [] }]

      expect(automation_rule).not_to be_valid
      expect(automation_rule.errors[:actions]).to include('Action 0: Required action parameters must not be empty.')
    end

    it 'rejects nominal SLA conditions without an implemented filter' do
      automation_rule.conditions = [{ attribute_key: 'sla_policy_id', filter_operator: 'equal_to', values: [12] }]

      expect(automation_rule).not_to be_valid
      expect(automation_rule.errors[:conditions]).to include('Condition 0: The attribute is unavailable in this account.')
    end
  end

  describe 'audit log' do
    context 'when automation rule is created' do
      it 'has associated audit log created' do
        expect(Audited::Audit.where(auditable_type: 'AutomationRule', action: 'create').count).to eq 1
      end
    end

    context 'when automation rule is updated' do
      it 'has associated audit log created' do
        automation_rule.update(name: 'automation rule 2')
        expect(Audited::Audit.where(auditable_type: 'AutomationRule', action: 'update').count).to eq 1
      end
    end

    context 'when automation rule is deleted' do
      it 'has associated audit log created' do
        automation_rule.destroy!
        expect(Audited::Audit.where(auditable_type: 'AutomationRule', action: 'destroy').count).to eq 1
      end
    end

    context 'when automation rule is in enterprise namespace' do
      it 'has associated sla methods available' do
        expect(automation_rule.conditions_attributes).to include('sla_policy_id')
        expect(automation_rule.actions_attributes).to include('add_sla')
      end
    end
  end
end
