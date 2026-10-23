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

  context 'with create_internal_task' do
    let(:action_name) { 'create_internal_task' }
    let(:action_params) { [{ 'title' => 'Call the customer' }] }

    [AutomationRule, Macro].each do |model|
      context "when saving #{model.name}" do
        let(:rule) { build(model == Macro ? :macro : :automation_rule, account: create(:account), actions: [action]) }

        it 'accepts the action with only a title' do
          expect(rule.save).to be(true)
        end

        it 'accepts an explicit account agent' do
          action_params.first['assignee_id'] = create(:user, account: rule.account, role: :agent).id

          expect(rule.save).to be(true)
        end

        it 'rejects an agent from another account with an action-specific error' do
          action_params.first['assignee_id'] = create(:user, account: create(:account), role: :agent).id

          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('create_internal_task', 'agent of the account')
        end

        it 'rejects an administrator who is not an agent of this account' do
          action_params.first['assignee_id'] = create(:user, account: rule.account, role: :administrator).id

          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('create_internal_task', 'agent of the account')
        end

        it 'rejects a user with no account membership' do
          action_params.first['assignee_id'] = create(:user).id

          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('create_internal_task')
        end

        wrong_assignee_ids = [nil, '1', true]
        wrong_assignee_ids.each do |id|
          it "rejects an assignee of the wrong type: #{id.inspect}" do
            action_params.first['assignee_id'] = id

            expect(rule.save).to be(false)
            expect(rule.errors[:actions].join).to include('create_internal_task')
          end
        end

        it 'rejects an empty title' do
          action_params.first['title'] = ' '

          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('create_internal_task', 'title')
        end

        it 'rejects a due date beyond the shared maximum' do
          action_params.first['due_in'] = { 'duration' => 366, 'unit' => 'days' }

          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('create_internal_task', '365 days')
        end

        it 'accepts a due date at the shared maximum' do
          action_params.first['due_in'] = { 'duration' => 365, 'unit' => 'days' }

          expect(rule.save).to be(true)
        end
      end
    end
  end

  context 'with snooze_conversation' do
    let(:action_name) { 'snooze_conversation' }

    [nil, [], { 'duration' => 3, 'unit' => 'days' }, [{ 'duration' => 2, 'unit' => 'hours' }],
     { 'duration' => 365, 'unit' => 'days' }, { 'duration' => 8760, 'unit' => 'hours' },
     { 'duration' => 525_600, 'unit' => 'minutes' }].each do |params|
      context "with valid parameters #{params.inspect}" do
        let(:action_params) { params }

        it 'allows the rule to be saved' do
          expect(validation.perform).to be_empty
          expect(rule.save).to be(true)
        end
      end
    end

    [0, -1, 1.5, '3', nil, true].each do |duration|
      context "with invalid duration #{duration.inspect}" do
        let(:action_params) { { 'duration' => duration, 'unit' => 'days' } }

        it 'rejects saving with an error naming the action' do
          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('snooze_conversation', 'positive integer')
        end
      end
    end

    [{ 'duration' => 366, 'unit' => 'days' }, { 'duration' => 8761, 'unit' => 'hours' },
     { 'duration' => 525_601, 'unit' => 'minutes' }, { 'duration' => 1, 'unit' => 'weeks' },
     { 'duration' => 1 }, {}, [nil], '3 days'].each do |params|
      context "with invalid parameters #{params.inspect}" do
        let(:action_params) { params }

        it 'rejects saving with an error naming the action' do
          expect(validation.perform.first[:message]).to include('snooze_conversation')
          expect(rule.save).to be(false)
          expect(rule.errors[:actions].join).to include('snooze_conversation')
        end
      end
    end
  end
end
