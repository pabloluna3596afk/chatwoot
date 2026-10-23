require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe AutomationRule do
  describe 'concerns' do
    it_behaves_like 'reauthorizable'
  end

  describe 'associations' do
    let(:account) { create(:account) }
    let(:params) do
      {
        name: 'Notify Conversation Created and mark priority query',
        description: 'Notify all administrator about conversation created and mark priority query',
        event_name: 'conversation_created',
        account_id: account.id,
        conditions: [
          {
            attribute_key: 'browser_language',
            filter_operator: 'equal_to',
            values: ['en'],
            query_operator: 'AND'
          },
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            values: %w[USA UK],
            query_operator: nil
          }
        ],
        actions: [
          {
            action_name: :send_message,
            action_params: ['Welcome to the chatwoot platform.']
          },
          {
            action_name: :assign_team,
            action_params: [1]
          },
          {
            action_name: :remove_assigned_agent
          },
          {
            action_name: :remove_assigned_team
          },
          {
            action_name: :add_label,
            action_params: %w[support priority_customer]
          },
          {
            action_name: :assign_agent,
            action_params: [1]
          }
        ]
      }.with_indifferent_access
    end

    it 'returns valid record' do
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'returns invalid record' do
      params[:conditions][0].delete('query_operator')
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be false
      expect(rule.errors.messages[:conditions]).to eq(['Automation conditions should have query operator.'])
    end

    it 'allows labels as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['bug'],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'validates label condition operators' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'is_present',
          values: [],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'allows private_note as a valid condition attribute' do
      params[:event_name] = 'message_created'
      params[:conditions] = [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [true],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end
  end

  describe 'the saved automation contract' do
    let(:account) { create(:account) }
    let(:rule) { build(:automation_rule, account: account) }
    let(:condition) { rule.conditions.first }

    it 'rejects unsupported events without changing active' do
      rule.event_name = 'contact_created'

      expect(rule).not_to be_valid
      expect(rule.errors[:event_name]).to include('is not supported')
      expect(rule.active).to be(true)
    end

    it 'names the condition with an unsupported operator' do
      condition['filter_operator'] = 'contains'

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The filter operator is not supported for this attribute.')
      expect(rule.active).to be(true)
    end

    it 'rejects message attributes on conversation events' do
      condition['attribute_key'] = 'content'

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The attribute is not supported for this event.')
    end

    it 'rejects nominal attributes with no implemented filter' do
      condition['attribute_key'] = 'hours_since_last_outgoing'

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The attribute is unavailable in this account.')
    end

    it 'rejects custom attributes from another account' do
      definition = create(:custom_attribute_definition, attribute_model: 'contact_attribute')
      condition['attribute_key'] = definition.attribute_key
      condition['custom_attribute_type'] = 'contact_attribute'

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The attribute is unavailable in this account.')
    end

    it 'validates custom operators by the attribute display type' do
      definition = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                                       attribute_display_type: 'checkbox')
      condition.merge!('attribute_key' => definition.attribute_key, 'filter_operator' => 'contains')

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The filter operator is not supported for this attribute.')
    end

    it 'rejects unknown schedule kinds' do
      rule.assign_attributes(event_name: 'time_triggered', schedule: { kind: 'whenever' })

      expect(rule).not_to be_valid
      expect(rule.errors[:schedule]).to include('kind is not supported')
    end

    it 'rejects execution delays on scheduled rules' do
      rule.assign_attributes(event_name: 'time_triggered', schedule: { kind: 'hours_since_last_incoming' }, execution_delay: 60)

      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('cannot be used with time_triggered events.')
    end

    it 'accepts the existing conversation schedule kinds' do
      %w[hours_since_last_outgoing hours_since_last_incoming].each do |kind|
        rule.assign_attributes(event_name: 'time_triggered', schedule: { kind: kind })

        expect(rule).to be_valid
      end
    end

    it 'rejects a query operator with an undocumented type' do
      condition['query_operator'] = 1

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions]).to include('Condition 0: The query operator must be AND or OR.')
    end

    it 'saves the five existing contact recipe payloads with WhatsApp template actions' do
      inbox = create(:inbox, account: account)
      schedules = [
        { attribute_key: 'birthday', recurrence: 'yearly', relative_to: 'on' },
        { attribute_key: 'anniversary', recurrence: 'yearly', relative_to: 'on' },
        { attribute_key: 'purchase', recurrence: 'once', relative_to: 'after', days: 30 },
        { attribute_key: 'appointment', recurrence: 'once', relative_to: 'before', days: 1 },
        { date_source: 'last_activity', recurrence: 'once', relative_to: 'after', days: 60 }
      ]
      schedules.each do |schedule|
        recipe = build(:automation_rule, account: account, event_name: 'time_triggered', conditions: [],
                                        schedule: schedule.merge(kind: 'contact_date', target_inbox_id: inbox.id),
                                        actions: [{ action_name: 'send_whatsapp_template',
                                                    action_params: [{ inbox_id: inbox.id, name: 'recipe', language: 'es' }] }])

        expect(recipe.save).to be(true)
      end
    end

    context 'with an invalid legacy definition' do
      let(:rule) { create(:automation_rule, account: account) }

      before do
        rule.update_columns(event_name: 'unsupported', # rubocop:disable Rails/SkipsModelValidations
                            conditions: [{ attribute_key: 'deleted', filter_operator: 'invalid' }],
                            actions: [{ action_name: 'deleted_action' }])
        rule.reload
      end

      it 'allows deactivation, reactivation and renaming' do
        expect(rule.update(active: false)).to be(true)
        expect(rule.update(active: true)).to be(true)
        expect(rule.update(name: 'Renamed legacy rule')).to be(true)
      end

      it 'validates the whole definition when any contract field changes' do
        rule.event_name = 'another_invalid_event'

        expect(rule).not_to be_valid
        expect(rule.errors.keys).to include(:event_name, :conditions, :actions)
        expect(rule.reload.active).to be(true)
      end

      it 'rejects a different invalid condition' do
        rule.conditions = [{ attribute_key: 'another_deleted_attribute', filter_operator: 'equal_to' }]

        expect(rule.save).to be(false)
        expect(rule.errors[:conditions]).to be_present
      end

      it 'rejects a different invalid action' do
        rule.actions = [{ action_name: 'another_deleted_action' }]

        expect(rule.save).to be(false)
        expect(rule.errors[:actions]).to include('Action 0: The action is not supported.')
      end
    end
  end

  describe 'schedule_format for time_triggered' do
    let(:account) { create(:account) }

    def time_rule(schedule)
      build(
        :automation_rule,
        account: account,
        event_name: 'time_triggered',
        conditions: [],
        actions: [{ 'action_name' => 'add_label', 'action_params' => ['seguimiento'] }],
        schedule: schedule
      )
    end

    it 'allows on without days' do
      rule = time_rule('kind' => 'days_since_attribute', 'attribute_key' => 'fecha_cita', 'relative_to' => 'on')
      expect(rule).to be_valid
    end

    it 'rejects after when days is missing or zero' do
      rule = time_rule('kind' => 'days_since_attribute', 'attribute_key' => 'fecha_cita', 'relative_to' => 'after')
      expect(rule).not_to be_valid
      expect(rule.errors[:schedule]).to include('days must be 1 or greater')
    end

    it 'rejects invalid relative_to' do
      rule = time_rule(
        'kind' => 'days_since_attribute',
        'attribute_key' => 'fecha_cita',
        'relative_to' => 'whenever',
        'days' => 3
      )
      expect(rule).not_to be_valid
      expect(rule.errors[:schedule]).to include('relative_to must be after, on, or before')
    end

    describe 'contact_date' do
      let!(:inbox) { create(:inbox, account: account) }

      def contact_rule(extra = {})
        time_rule({ 'kind' => 'contact_date', 'target_inbox_id' => inbox.id }.merge(extra))
      end

      it 'allows a yearly attribute rule with no days (birthday)' do
        rule = contact_rule('date_source' => 'contact_attribute', 'attribute_key' => 'cumpleanos',
                            'recurrence' => 'yearly', 'relative_to' => 'on')
        expect(rule).to be_valid
      end

      it 'allows a one-shot attribute rule with days (repurchase)' do
        rule = contact_rule('date_source' => 'contact_attribute', 'attribute_key' => 'fecha_compra',
                            'recurrence' => 'once', 'relative_to' => 'after', 'days' => 30)
        expect(rule).to be_valid
      end

      it 'allows a last_activity rule with no attribute_key (win-back)' do
        rule = contact_rule('date_source' => 'last_activity', 'relative_to' => 'after', 'days' => 60)
        expect(rule).to be_valid
      end

      it 'defaults date_source, recurrence and relative_to when absent' do
        rule = contact_rule('attribute_key' => 'cumpleanos')
        expect(rule).to be_valid
      end

      it 'requires attribute_key for an attribute source' do
        rule = contact_rule('date_source' => 'contact_attribute')
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule]).to include('attribute_key is required')
      end

      it 'rejects an unknown date_source' do
        rule = contact_rule('date_source' => 'astrologia', 'attribute_key' => 'x')
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule].first).to include('date_source must be one of')
      end

      it 'rejects yearly recurrence on last_activity, which never comes around again' do
        rule = contact_rule('date_source' => 'last_activity', 'recurrence' => 'yearly')
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule]).to include('recurrence yearly requires a contact_attribute date_source')
      end

      it 'requires target_inbox_id' do
        rule = time_rule('kind' => 'contact_date', 'attribute_key' => 'cumpleanos')
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule]).to include('target_inbox_id is required')
      end

      it 'rejects a target_inbox_id from another account' do
        other_inbox = create(:inbox, account: create(:account))
        rule = time_rule('kind' => 'contact_date', 'attribute_key' => 'cumpleanos', 'target_inbox_id' => other_inbox.id)
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule]).to include('target_inbox_id must belong to the account')
      end

      it 'rejects before/after when days is missing or zero' do
        rule = contact_rule('attribute_key' => 'cumpleanos', 'relative_to' => 'before')
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule]).to include('days must be 1 or greater')
      end
    end

    it 'flags contact_based_schedule? only for contact-scoped kinds' do
      contact_rule = time_rule(
        'kind' => 'contact_date', 'attribute_key' => 'cumpleanos', 'target_inbox_id' => create(:inbox, account: account).id
      )
      days_rule = time_rule('kind' => 'days_since_attribute', 'attribute_key' => 'fecha_cita', 'relative_to' => 'on')

      expect(contact_rule.contact_based_schedule?).to be(true)
      expect(days_rule.contact_based_schedule?).to be(false)
    end
  end

  describe 'reauthorizable' do
    context 'when prompt_reauthorization!' do
      it 'marks the rule inactive' do
        rule = create(:automation_rule)
        expect(rule.active).to be true
        rule.prompt_reauthorization!
        expect(rule.active).to be false
      end
    end

    context 'when reauthorization_required?' do
      it 'unsets the error count if conditions are updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(conditions: [{ attribute_key: 'browser_language', filter_operator: 'equal_to', values: ['en'], query_operator: 'AND' }])
        expect(rule.reauthorization_required?).to be false
      end

      it 'will not unset the error count if conditions are not updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(name: 'Updated name')
        expect(rule.reauthorization_required?).to be true
      end
    end
  end

  describe 'execution_delay validations' do
    let(:rule) { build(:automation_rule, account: create(:account)) }

    it 'allows nil (immediate execution)' do
      rule.execution_delay = nil
      expect(rule).to be_valid
    end

    it 'allows delays between 10 minutes and 30 days' do
      rule.execution_delay = 240
      expect(rule).to be_valid
    end

    it 'rejects delays below 10 minutes' do
      rule.execution_delay = 5
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to be_present
    end

    it 'rejects delays above 30 days' do
      rule.execution_delay = 43_201
      expect(rule).not_to be_valid
    end

    it 'rejects non-integer delays' do
      rule.execution_delay = 10.5
      expect(rule).not_to be_valid
    end

    it 'rejects a delay combined with an attribute_changed condition' do
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'attribute_changed',
                           'values' => { 'from' => ['open'], 'to' => ['pending'] }, 'query_operator' => nil }]
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('cannot be used with attribute_changed conditions.')
    end

    it 'allows a delayed message rule with a label condition' do
      rule.event_name = 'message_created'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to',
                           'values' => ['feature'], 'query_operator' => nil }]

      expect(rule).to be_valid
    end

    it 'rejects a delayed conversation-level rule with a label condition' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to',
                           'values' => ['feature'], 'query_operator' => nil }]

      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('only supports status and inbox conditions for conversation-level events.')
    end

    it 'rejects a delayed conversation-level rule with a mutable non-status condition' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'priority', 'filter_operator' => 'equal_to', 'values' => ['urgent'], 'query_operator' => nil }]
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('only supports status and inbox conditions for conversation-level events.')
    end

    it 'allows a delayed conversation-level rule with only status conditions' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed conversation_created rule (arms on creation)' do
      rule.event_name = 'conversation_created'
      rule.execution_delay = 10
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed conversation-level rule scoped by status and inbox (immutable)' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => 'AND' },
                         { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [1], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed message_created rule with a non-status condition' do
      rule.event_name = 'message_created'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['outgoing'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end
  end

  describe 'discarding stale pending executions on edit' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account, status: :pending) }
    let(:status_condition) { { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => nil } }
    let(:rule) do
      create(:automation_rule, account: account, event_name: 'conversation_updated', execution_delay: 60,
                               conditions: [status_condition], actions: [{ 'action_name' => 'add_label', 'action_params' => ['stale'] }])
    end

    before { AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation) }

    it 'discards armed rows when the actions change' do
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.pending).to be_empty
    end

    it 'discards armed rows when the delay changes' do
      rule.update!(execution_delay: 120)
      expect(rule.pending_executions.pending).to be_empty
    end

    it 'discards armed rows when the rule is deactivated, so reactivating cannot resurrect them' do
      rule.update!(active: false)
      expect(rule.pending_executions.armed).to be_empty

      rule.update!(active: true)
      expect(rule.pending_executions.armed).to be_empty
    end

    it 'discards a stale processing row that the sweep would otherwise reclaim' do
      rule.pending_executions.first.update!(status: :processing)
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.armed).to be_empty
    end

    it 'leaves an executing row alone because its actions are already in flight' do
      rule.pending_executions.first.update!(status: :executing)
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.executing.count).to eq(1)
    end

    it 'frees the episode slot so the new definition re-arms for the same episode' do
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation)
      expect(rule.pending_executions.pending.count).to eq(1)
    end

    it 'leaves armed rows untouched on a name-only edit' do
      rule.update!(name: 'Renamed rule')
      expect(rule.pending_executions.pending.count).to eq(1)
    end
  end
end
