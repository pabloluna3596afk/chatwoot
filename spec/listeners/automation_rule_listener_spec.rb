require 'rails_helper'

describe AutomationRuleListener do
  let(:id_offsets) { [2, 0, 1] }
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:conditions_filter_service) { double }
  let(:condition_match) { double }
  let(:action_service) { double }

  before do
    allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
    allow(conditions_filter_service).to receive(:perform).and_return(condition_match)
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
    allow(action_service).to receive(:perform)
  end

  describe 'computed conversation conditions' do
    before { allow(AutomationRules::ConditionsFilterService).to receive(:new).and_call_original }

    shared_values = { 'channel_type' => 'web_widget', 'within_business_hours' => true, 'captain_state' => 'none' }

    %w[conversation_created conversation_updated conversation_opened conversation_resolved message_created].each do |event_name|
      it "evaluates the shared conditions for #{event_name}" do
        message = create(:message, conversation: conversation, account: account, message_type: :incoming)
        conditions = shared_values.map do |key, value|
          { attribute_key: key, filter_operator: 'equal_to', values: [value], query_operator: 'AND' }
        end
        conditions.last[:query_operator] = nil
        rule = create(:automation_rule, account: account, event_name: event_name, conditions: conditions)
        event = Events::Base.new(event_name, Time.current, conversation: conversation, message: message)

        listener.public_send(event_name, event)
        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation).once

        rule.update!(conditions: [{ attribute_key: 'channel_type', filter_operator: 'equal_to', values: ['whatsapp'] }])
        listener.public_send(event_name, event)
        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation).once
      end
    end
  end

  describe 'campaign conditions' do
    before do
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_call_original
    end

    %w[conversation_created conversation_updated conversation_opened conversation_resolved message_created].each do |event_name|
      it "runs #{event_name} only when the conversation belongs to the selected campaign" do
        campaign = create(:campaign, account: account)
        rule = create(:automation_rule, account: account, event_name: event_name, conditions: [
                        { 'attribute_key' => 'campaign_id', 'filter_operator' => 'equal_to', 'values' => [campaign.id] }
                      ])
        conversation.update!(campaign_id: campaign.id)
        message = create(:message, account: account, conversation: conversation, message_type: :incoming)
        event = Events::Base.new(event_name, Time.current, conversation: conversation, message: message)

        listener.public_send(event_name, event)
        conversation.update!(campaign_id: nil)
        listener.public_send(event_name, event)

        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation).once
      end
    end
  end

  describe 'execution order' do
    before do
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_call_original
      allow(AutomationRules::ActionService).to receive(:new).and_call_original
    end

    %w[conversation_created conversation_updated conversation_opened conversation_resolved message_created].each do |event_name|
      it "executes #{event_name} rules by ascending ID and keeps the same winning assignee" do
        conversation.update!(status: :open)
        message = create(:message, conversation: conversation, account: account)
        base_id = AutomationRule.maximum(:id).to_i + 1000
        rules = id_offsets.map do |offset|
          agent = create(:user, account: account)
          create(:inbox_member, inbox: conversation.inbox, user: agent)
          create(:automation_rule, id: base_id + offset, account: account, event_name: event_name,
                                   conditions: [{ attribute_key: 'status', filter_operator: 'equal_to',
                                                  values: ['open'], query_operator: nil }],
                                   actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
        end
        event = Events::Base.new(event_name, Time.current, conversation: conversation, message: message)
        executed_ids = []
        allow(AutomationRules::ActionService).to receive(:new).and_wrap_original do |original, rule, *args|
          executed_ids << rule.id
          original.call(rule, *args)
        end

        2.times do
          conversation.update!(assignee: nil)
          listener.public_send(event_name, event)
          expect(conversation.reload.assignee_id).to eq(rules.first.actions.first['action_params'].first)
        end

        expect(executed_ids).to eq(rules.map(&:id).sort * 2)
      end
    end

    it 'still excludes inactive, other-account, other-event and nonmatching rules' do
      conversation.update!(status: :open)
      condition = { attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }
      matching = create(:automation_rule, account: account, event_name: 'conversation_created', conditions: [condition],
                                          actions: [{ action_name: 'change_priority', action_params: ['high'] }])
      create(:automation_rule, account: account, event_name: 'conversation_created', conditions: [condition], active: false)
      create(:automation_rule, event_name: 'conversation_created', conditions: [condition])
      create(:automation_rule, account: account, event_name: 'conversation_opened', conditions: [condition])
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: [condition.merge(values: ['resolved'])])
      event = Events::Base.new('conversation_created', Time.current, conversation: conversation)

      listener.conversation_created(event)

      expect(AutomationRules::ActionService).to have_received(:new).with(matching, account, conversation).once
      expect(AutomationRules::ActionService).to have_received(:new).once
      expect(conversation.reload.priority).to eq('high')
    end

    it 'merges delayed update rules into creation rules in ascending ID order' do
      conversation.update!(status: :open)
      base_id = AutomationRule.maximum(:id).to_i + 1000
      instant = create(:automation_rule, id: base_id + 1, account: account, event_name: 'conversation_created')
      delayed = create(:automation_rule, id: base_id, account: account, event_name: 'conversation_updated',
                                         execution_delay: 10)

      expect(listener.send(:conversation_rules, 'conversation_created', account).map(&:id)).to eq([delayed.id, instant.id])
    end
  end

  describe 'conversation_created' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_created', account: account) }
    let(:event) do
      Events::Base.new('conversation_created', Time.zone.now, { conversation: conversation,
                                                                changed_attributes: { status: %w[nil Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_created', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conversation has auto_reply in additional_attributes' do
        conversation.additional_attributes = { 'auto_reply' => true }
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_updated' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_updated', account: account) }
    let(:event) do
      Events::Base.new('conversation_updated', Time.zone.now, { conversation: conversation,
                                                                changed_attributes: { status: %w[Resolved Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_updated', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_opened' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_opened', account: account) }
    let(:event) do
      Events::Base.new('conversation_opened', Time.zone.now, { conversation: conversation,
                                                               changed_attributes: { status: %w[Resolved Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_opened', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_resolved' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_resolved', account: account) }
    let(:event) do
      Events::Base.new('conversation_resolved', Time.zone.now, { conversation: conversation,
                                                                 changed_attributes: { status: %w[Snoozed Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_resolved', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'message_created' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'message_created', account: account) }
    let!(:message) { create(:message, account: account, conversation: conversation) }
    let(:event) do
      Events::Base.new('message_created', Time.zone.now, { message: message,
                                                           changed_attributes: { content: %w[nil Hi] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'message_created', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if message is activity message' do
        message.update!(message_type: 'activity')
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if message is auto reply email' do
        email_channel = create(:channel_email, account: account)
        email_inbox = create(:inbox, channel: email_channel, account: account)
        email_conversation = create(:conversation, inbox: email_inbox, account: account)
        email_message = create(:message, conversation: email_conversation, account: account,
                                         content_attributes: { email: { auto_reply: true } })
        email_event = Events::Base.new('message_created', Time.zone.now, { message: email_message })
        allow(condition_match).to receive(:present?).and_return(true)

        listener.message_created(email_event)
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end

      it 'calls AutomationRules::ActionService if message is a private note' do
        message.update!(private: true)
        allow(condition_match).to receive(:present?).and_return(true)

        listener.message_created(event)

        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match based on content' do
        message.update!(processed_message_content: 'hi', content: "hi\n\nhello")
        allow(condition_match).to receive(:present?).and_return(false)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'passes conversation attributes to conditions filter service' do
        conversation.update!(status: :open, priority: :high)
        listener.message_created(event)
        expect(AutomationRules::ConditionsFilterService).to have_received(:new).with(
          automation_rule,
          conversation,
          { message: message, changed_attributes: { content: %w[nil Hi] } }
        )
      end
    end
  end

  describe 'delayed rules' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_updated', account: account, execution_delay: 60) }
    let(:event) do
      Events::Base.new('conversation_updated', Time.zone.now, { conversation: conversation, changed_attributes: {} })
    end

    before { allow(condition_match).to receive(:present?).and_return(true) }

    context 'when the delayed_automations feature is enabled' do
      before { account.enable_features!('delayed_automations') }

      it 'records a pending execution instead of running actions' do
        expect { listener.conversation_updated(event) }.to change(AutomationRulePendingExecution, :count).by(1)
        expect(AutomationRules::ActionService).not_to have_received(:new)
        expect(AutomationRulePendingExecution.last.due_at).to be_within(5.seconds).of(60.minutes.from_now)
      end

      it 'still runs rules without a delay immediately' do
        automation_rule.update!(execution_delay: nil)

        expect { listener.conversation_updated(event) }.not_to change(AutomationRulePendingExecution, :count)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end
    end

    context 'when the delayed_automations feature is disabled' do
      it 'neither arms a pending execution nor falls back to immediate execution' do
        expect { listener.conversation_updated(event) }.not_to change(AutomationRulePendingExecution, :count)
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end
    end
  end

  # The builder's "customer unresponsive" trigger writes message_type = outgoing plus
  # private_note = false. A pending status condition can be joined to those structural conditions
  # so the follow-up only arms while the conversation is pending.
  describe 'the curated customer-unresponsive trigger' do
    let(:automation_rule) do
      create(:automation_rule, account: account, event_name: 'message_created', execution_delay: 60,
                               conditions: [
                                 { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to',
                                   'values' => ['outgoing'], 'query_operator' => 'and' },
                                 { 'attribute_key' => 'private_note', 'filter_operator' => 'equal_to',
                                   'values' => [false], 'query_operator' => 'and' },
                                 { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to',
                                   'values' => [conversation.inbox_id], 'query_operator' => 'and' },
                                 { 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                                   'values' => ['pending'], 'query_operator' => nil }
                               ],
                               actions: [{ 'action_name' => 'add_label', 'action_params' => ['stale'] }])
    end

    before do
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_call_original
      account.enable_features!('delayed_automations')
      automation_rule
    end

    it 'arms the wait on a real agent reply' do
      conversation.pending!
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing)
      event = Events::Base.new('message_created', Time.zone.now, { message: reply })

      expect { listener.message_created(event) }.to change(AutomationRulePendingExecution, :count).by(1)
      expect(AutomationRulePendingExecution.last.automation_rule).to eq(automation_rule)
    end

    it 'does not arm the wait on a private note' do
      conversation.pending!
      note = create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true)
      event = Events::Base.new('message_created', Time.zone.now, { message: note })

      expect { listener.message_created(event) }.not_to change(AutomationRulePendingExecution, :count)
    end

    it 'does not arm the wait when the conversation is not pending' do
      conversation.open!
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing)
      event = Events::Base.new('message_created', Time.zone.now, { message: reply })

      expect { listener.message_created(event) }.not_to change(AutomationRulePendingExecution, :count)
    end
  end

  describe 'execution history' do
    let!(:history_rule) do
      create(:automation_rule, account: account, event_name: 'conversation_created', conditions: [],
                               actions: [{ 'action_name' => 'add_label', 'action_params' => ['history'] }])
    end
    let(:event) { Events::Base.new('conversation_created', Time.current, conversation: conversation) }

    before do
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_call_original
      allow(AutomationRules::ActionService).to receive(:new).and_call_original
    end

    it 'records exactly one run for the event' do
      listener.conversation_created(event)

      expect(history_rule.runs.sole).to have_attributes(outcome: 'executed', event_name: 'conversation_created')
      expect(history_rule.runs.sole.details['actions']).to eq([{ 'name' => 'add_label', 'outcome' => 'ok' }])
    end

    it 'does not record nonmatching evaluations' do
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
      allow(conditions_filter_service).to receive(:perform).and_return(false)
      listener.conversation_created(event)

      expect(history_rule.runs).to be_empty
    end
  end
end
