require 'rails_helper'

RSpec.describe AutomationRules::ActionValidationService do
  subject(:validation) { described_class.new(rule) }

  let(:rule) { build(:automation_rule, account: create(:account), actions: [action]) }
  let(:action) { { 'action_name' => action_name, 'action_params' => action_params } }
  let(:action_name) { 'send_message' }
  let(:action_params) { [] }

  it 'identifies actions missing required parameters' do
    expect(validation.perform).to eq([{ action_index: 0, message: 'Message content must not be empty.' }])
  end

  it 'uses the same action catalog as the model, including Enterprise extensions' do
    rule.actions_attributes.each do |name|
      action['action_name'] = name

      expect(validation.perform.pluck(:message)).not_to include('The action is not supported.')
    end
  end

  it 'reports the position of unknown actions' do
    rule.actions = [{ 'action_name' => 'notify_assignee' }, { 'action_name' => 'unknown' }]

    expect(validation.perform).to eq([{ action_index: 1, message: 'The action is not supported.' }])
  end

  it 'accepts the actions whose implementation requires no parameters' do
    described_class::PARAMETERLESS_ACTIONS.each do |name|
      action['action_name'] = name

      expect(validation.perform).to be_empty
    end
  end

  it 'rejects blank array entries' do
    action['action_params'] = [' ']

    expect(validation.perform).to be_present
  end

  it 'accepts Captain selectors and saved macros' do
    [['assign_agent', 'captain'], ['assign_agent', 'captain:12'], ['execute_macro', 42]].each do |name, value|
      rule.actions = [{ 'action_name' => name, 'action_params' => [value] }]

      expect(validation.perform).to be_empty
      expect(rule).to be_valid
    end
  end

  context 'with a structured action' do
    let(:action_name) { 'send_whatsapp_template' }
    let(:action_params) { [{ 'inbox_id' => 1, 'name' => 'birthday', 'language' => 'es' }] }

    it 'accepts a template without optional components' do
      expect(validation.perform).to be_empty
    end

    it 'requires each mandatory template field' do
      action_params.first.delete('language')

      expect(validation.perform.first[:message]).to include('language')
    end

    it 'requires the email message and team ids' do
      rule.actions = [{ 'action_name' => 'send_email_to_team', 'action_params' => [{ 'team_ids' => [] }] }]

      expect(validation.perform.first[:message]).to include('team_ids, message')
    end

    it 'requires a custom attribute key while allowing values to be cleared' do
      rule.actions = [{ 'action_name' => 'update_contact_custom_attribute', 'action_params' => [{ 'value' => false }] }]
      expect(validation.perform.first[:message]).to include('attribute_key')

      rule.actions.first['action_params'].first['attribute_key'] = 'subscribed'
      expect(validation.perform).to be_empty
    end
  end
end
