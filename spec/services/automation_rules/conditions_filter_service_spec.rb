require 'rails_helper'

RSpec.describe AutomationRules::ConditionsFilterService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:email_channel) { create(:channel_email, account: account) }
  let(:email_inbox) { create(:inbox, channel: email_channel, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation, content: 'test text', inbox: conversation.inbox, message_type: :incoming)
  end
  let(:rule) { create(:automation_rule, account: account) }

  before do
    conversation = create(:conversation, account: account)
    conversation.contact.update(phone_number: '+918484828282', email: 'test@test.com')
    create(:conversation, account: account)
    create(:conversation, account: account)
  end

  describe 'computed conversation conditions' do
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
    let(:rule) { build(:automation_rule, account: account, conditions: [condition]) }
    let(:condition) { { 'attribute_key' => key, 'filter_operator' => operator, 'values' => [value] } }
    let(:operator) { 'equal_to' }

    context 'with channel_type' do
      let(:key) { 'channel_type' }
      let(:value) { 'whatsapp' }

      [[:channel_whatsapp, { provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false }, {}, 'whatsapp'],
       [:channel_twilio_sms, { medium: :whatsapp }, {}, 'whatsapp'],
       [:channel_twilio_sms, { medium: :sms }, {}, 'sms'],
       [:channel_instagram, {}, {}, 'instagram'],
       [:channel_facebook_page, {}, { 'type' => 'instagram_direct_message' }, 'instagram'],
       [:channel_facebook_page, {}, {}, 'messenger'],
       [:channel_widget, {}, {}, 'web_widget'],
       [:channel_email, {}, {}, 'email'],
       [:channel_api, {}, {}, 'api']].each do |factory, attributes, additional_attributes, expected|
        context "with #{factory}, #{attributes} and #{additional_attributes}" do
          before do
            allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
            channel = create(factory, **attributes, account: account)
            inbox.update!(channel: channel)
            conversation.update!(additional_attributes: additional_attributes)
          end

          it "matches only #{expected} and reverses not_equal_to" do
            expect(described_class.new(rule, conversation).evaluate).to eq(expected == value)
            rule.conditions = [condition.merge('filter_operator' => 'not_equal_to')]
            expect(described_class.new(rule, conversation).evaluate).to eq(expected != value)
            rule.conditions = [condition.merge('values' => [expected])]
            expect(described_class.new(rule, conversation).evaluate).to be(true)
          end
        end
      end
    end

    context 'with within_business_hours' do
      let(:key) { 'within_business_hours' }
      let(:value) { false }

      before { inbox.update!(working_hours_enabled: true, timezone: 'America/Guayaquil') }

      [['2026-10-26 14:00:00 UTC', true], ['2026-10-26 23:00:00 UTC', false],
       ['2026-10-25 15:00:00 UTC', false]].each do |time, working|
        it "uses the inbox timezone and schedule at #{time}" do
          travel_to(Time.zone.parse(time)) do
            expect(described_class.new(rule, conversation).evaluate).to eq(!working)
            rule.conditions = [condition.merge('values' => [true])]
            expect(described_class.new(rule, conversation).evaluate).to eq(working)
          end
        end
      end

      it 'always treats an inbox without enabled hours as open' do
        inbox.update!(working_hours_enabled: false)
        travel_to(Time.parse('2026-10-25 23:00:00 UTC')) do
          expect(described_class.new(rule, conversation).evaluate).to be(false)
          rule.conditions = [condition.merge('values' => [true])]
          expect(described_class.new(rule, conversation).evaluate).to be(true)
        end
      end
    end

    context 'with captain_state' do
      let(:key) { 'captain_state' }
      let(:value) { 'none' }

      %w[none ai escalated].each do |state|
        it "distinguishes #{state} using the conversation state" do
          if state == 'ai'
            # Represent Captain ownership without requiring an Enterprise assistant in the OSS evaluator spec.
            # rubocop:disable Rails/SkipsModelValidations
            conversation.update_columns(status: Conversation.statuses.fetch('pending'), ai_assignee_type: 'Captain::Assistant')
            # rubocop:enable Rails/SkipsModelValidations
          elsif state == 'escalated'
            conversation.update!(captain_handed_off_at: Time.current)
          end

          expect(conversation.captain_state || 'none').to eq(state)
          %w[none ai escalated].each do |expected|
            rule.conditions = [condition.merge('values' => [expected])]
            expect(described_class.new(rule, conversation).evaluate).to eq(expected == state)
            rule.conditions = [condition.merge('values' => [expected], 'filter_operator' => 'not_equal_to')]
            expect(described_class.new(rule, conversation).evaluate).to eq(expected != state)
          end
        end
      end
    end

    context 'when combined with existing conditions' do
      let(:key) { 'within_business_hours' }
      let(:value) { true }
      let(:status_condition) { { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['resolved'] } }

      it 'preserves AND and OR with computed conditions on either side' do
        { 'AND' => false, 'OR' => true }.each do |query_operator, expected|
          rule.conditions = [condition.merge('query_operator' => query_operator), status_condition]
          expect(described_class.new(rule, conversation).evaluate).to eq(expected)
          rule.conditions = [status_condition.merge('query_operator' => query_operator), condition]
          expect(described_class.new(rule, conversation).evaluate).to eq(expected)
        end
      end
    end
  end

  describe '#perform' do
    context 'with campaign_id conditions' do
      let(:campaign) { create(:campaign, account: account) }
      let(:other_campaign) { create(:campaign, account: account) }

      operator_expectations = {
        'equal_to' => [true, false, false],
        'not_equal_to' => [false, true, false],
        'is_present' => [true, true, false],
        'is_not_present' => [false, false, true]
      }

      AutomationRules::ConditionValidationService::EVENTS.each do |event|
        context "when the event is #{event}" do
          let(:rule) do
            build(:automation_rule, account: account, event_name: event,
                                    schedule: event == 'time_triggered' ? { kind: 'hours_since_last_incoming' } : {})
          end

          operator_expectations.each do |operator, expected|
            it "evaluates #{operator} against the conversation campaign, including NULL" do
              values = operator.in?(%w[is_present is_not_present]) ? [] : [campaign.id]
              rule.conditions = [{ 'attribute_key' => 'campaign_id', 'filter_operator' => operator, 'values' => values }]
              rule.save!
              options = event == 'message_created' ? { message: message } : {}

              [campaign.id, other_campaign.id, nil].zip(expected).each do |campaign_id, matches|
                conversation.update!(campaign_id: campaign_id)

                expect(described_class.new(rule, conversation, options).perform).to be(matches)
              end
            end
          end
        end
      end

      it 'combines campaign membership with the incoming message condition' do
        conversation.update!(campaign_id: campaign.id)
        rule.update!(event_name: 'message_created', conditions: [
                       { 'attribute_key' => 'campaign_id', 'filter_operator' => 'equal_to',
                         'values' => [campaign.id], 'query_operator' => 'AND' },
                       { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['incoming'] }
                     ])

        expect(described_class.new(rule, conversation, message: message).perform).to be(true)
        message.update!(message_type: :outgoing)
        expect(described_class.new(rule, conversation, message: message).perform).to be(false)
      end
    end

    context 'with an invalid legacy condition' do
      before do
        rule.update_columns(conditions: [ # rubocop:disable Rails/SkipsModelValidations
                              { 'attribute_key' => 'status', 'filter_operator' => 'unsupported', 'values' => ['open'] }
                            ])
      end

      it 'keeps the runtime authorization error reaction' do
        expect(rule).to receive(:authorization_error!).twice.and_call_original

        2.times do
          expect(described_class.new(rule, conversation).perform).to be(false)
        end

        expect(rule.authorization_error_count).to eq(2)
        expect(rule.reauthorization_required?).to be(true)
      end

      it 'disables the rule and enqueues the notification when the threshold is reached' do
        rule.authorization_error!

        expect do
          expect(described_class.new(rule, conversation).perform).to be(false)
        end.to have_enqueued_mail(AdministratorNotifications::AccountNotificationMailer, :automation_rule_disabled)
          .with(params: { account: account }, args: [rule])

        expect(rule.reload.active).to be(false)
        expect(rule.runs.sole).to have_attributes(outcome: 'failed', reason: 'rule_invalid_disabled')
      end
    end

    context 'when conditions based on filter_operator equal_to' do
      before do
        rule.conditions = [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }]
        rule.save
      end

      context 'when conditions in rule matches with object' do
        it 'will return true' do
          expect(described_class.new(rule, conversation, { changed_attributes: { status: [nil, 'open'] } }).perform).to be(true)
        end
      end

      context 'when conditions in rule does not match with object' do
        it 'will return false' do
          conversation.update(status: 'resolved')
          expect(described_class.new(rule, conversation, { changed_attributes: { status: %w[open resolved] } }).perform).to be(false)
        end
      end
    end

    context 'when conditions based on filter_operator start_with' do
      before do
        contact = conversation.contact
        contact.update(phone_number: '+918484848484')
        rule.conditions = [
          { 'values': ['+918484'], 'attribute_key': 'phone_number', 'query_operator': 'OR', 'filter_operator': 'starts_with' },
          { 'values': ['test'], 'attribute_key': 'email', 'query_operator': nil, 'filter_operator': 'contains' }
        ]
        rule.save
      end

      context 'when conditions in rule matches with object' do
        it 'will return true' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end
      end

      context 'when conditions in rule does not match with object' do
        it 'will return false' do
          conversation.contact.update(phone_number: '+918585858585')
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end
    end

    context 'when conditions check assignee presence' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before do
        conversation.update!(ai_assignee: agent_bot)
      end

      it 'treats AgentBot ownership as present' do
        rule.update!(conditions: [{ 'values': [], 'attribute_key': 'assignee_id', 'query_operator': nil, 'filter_operator': 'is_present' }])

        expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
      end

      it 'does not treat AgentBot ownership as absent' do
        rule.update!(conditions: [
                       { 'values': [], 'attribute_key': 'assignee_id', 'query_operator': nil, 'filter_operator': 'is_not_present' }
                     ])

        expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
      end
    end

    context 'when conditions based on messages attributes' do
      before { rule.update!(event_name: 'message_created') }

      context 'when filter_operator is equal_to' do
        before do
          rule.conditions = [
            { 'values': ['test text'], 'attribute_key': 'content', 'query_operator': 'AND', 'filter_operator': 'equal_to' },
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when conditions matches' do
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conditions in rule does not match' do
          message.update!(message_type: :outgoing)
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filtering private notes' do
        before do
          rule.conditions = [
            { 'values': [true], 'attribute_key': 'private_note', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when the message is a private note' do
          message.update!(private: true)

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when the message is not a private note' do
          message.update!(private: false)

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is on processed_message_content' do
        before do
          rule.conditions = [
            { 'values': ['help'], 'attribute_key': 'content', 'query_operator': 'AND', 'filter_operator': 'contains' },
            { 'values': ['incoming'], 'attribute_key': 'message_type', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        let(:conversation) { create(:conversation, account: account, inbox: email_inbox) }
        let(:message) do
          create(:message, account: account, conversation: conversation, content: "We will help you\n\n\n test",
                           inbox: conversation.inbox, message_type: :incoming,
                           content_attributes: { email: { text_content: { quoted: 'We will help you' } } })
        end

        it 'will return true for processed_message_content matches' do
          message
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when processed_message_content does no match' do
          rule.update(conditions: [
                        { 'values': ['text'], 'attribute_key': 'content', 'query_operator': nil, 'filter_operator': 'contains' }
                      ])

          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filtering messages based on conversation attributes' do
        let(:conversation) { create(:conversation, account: account, status: :open, priority: :high) }
        let(:message) do
          create(:message, account: account, conversation: conversation, content: 'Test message',
                           inbox: conversation.inbox, message_type: :incoming)
        end

        it 'will return true when conversation status matches' do
          rule.update(conditions: [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation status does not match' do
          rule.update(conditions: [
                        { 'values': ['resolved'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }
                      ])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(false)
        end

        it 'will return true when conversation priority matches' do
          rule.update(conditions: [
                        { 'values': ['high'], 'attribute_key': 'priority', 'query_operator': nil, 'filter_operator': 'equal_to' }
                      ])
          expect(described_class.new(rule, conversation, { message: message, changed_attributes: {} }).perform).to be(true)
        end
      end
    end

    context 'when conditions based on labels' do
      before do
        conversation.add_labels(['bug'])
      end

      context 'when filter_operator is equal_to' do
        before do
          rule.conditions = [
            { 'values': ['bug'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
        end

        it 'will return true when conversation has the label' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation does not have the label' do
          rule.conditions = [
            { 'values': ['feature'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'equal_to' }
          ]
          rule.save
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is not_equal_to' do
        before do
          rule.conditions = [
            { 'values': ['feature'], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'not_equal_to' }
          ]
          rule.save
        end

        it 'will return true when conversation does not have the label' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation has the label' do
          conversation.update_labels(%w[bug feature])
          expect(conversation.reload.label_list).to match_array(%w[bug feature])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end

        it 'will return false when conversation has any excluded label' do
          rule.update!(conditions: [
                         { 'values': %w[feature enterprise], 'attribute_key': 'labels', 'query_operator': nil,
                           'filter_operator': 'not_equal_to' }
                       ])
          conversation.update_labels(%w[bug enterprise])

          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is is_present' do
        before do
          rule.conditions = [
            { 'values': [], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'is_present' }
          ]
          rule.save
        end

        it 'will return true when conversation has any labels' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end

        it 'will return false when conversation has no labels' do
          conversation.update_labels([])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end
      end

      context 'when filter_operator is is_not_present' do
        before do
          rule.conditions = [
            { 'values': [], 'attribute_key': 'labels', 'query_operator': nil, 'filter_operator': 'is_not_present' }
          ]
          rule.save
        end

        it 'will return false when conversation has any labels' do
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
        end

        it 'will return true when conversation has no labels' do
          conversation.update_labels([])
          expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
        end
      end
    end

    context 'when conditions based on contact country_code' do
      before do
        conversation.update(additional_attributes: { country_code: 'US' })
        conversation.contact.update(additional_attributes: { country_code: 'IN' })
        rule.conditions = [
          { 'values': ['IN'], 'attribute_key': 'country_code', 'query_operator': nil, 'filter_operator': 'equal_to' }
        ]
        rule.save
      end

      it 'matches against the contact additional_attributes' do
        expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(true)
      end

      it 'returns false when the contact country_code does not match' do
        conversation.contact.update(additional_attributes: { country_code: 'GB' })
        expect(described_class.new(rule, conversation, { changed_attributes: {} }).perform).to be(false)
      end
    end
  end
end
