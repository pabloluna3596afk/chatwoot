# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Automations::ContactBasedRuleRunner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: true, record_run: true) }

  def contact_with(attrs)
    create(:contact, account: account, **attrs)
  end

  def build_rule(schedule_extra)
    schedule = {
      'kind' => 'contact_date',
      'target_inbox_id' => inbox.id
    }.merge(schedule_extra)

    create(
      :automation_rule,
      account: account,
      event_name: 'time_triggered',
      conditions: [],
      actions: [{ 'action_name' => 'send_message', 'action_params' => ['Hola!'] }],
      schedule: schedule
    )
  end

  before do
    allow(AutomationRules::ActionService).to receive(:new) do |_rule, _account, conversation|
      allow(action_service).to receive(:perform) do
        conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Hola!')
      end
      action_service
    end
  end

  around do |example|
    Time.use_zone('UTC') { example.run }
  end

  describe '#perform with a campaign condition' do
    it 'evaluates the resolved conversation before reserving sends or claiming a window' do
      campaign = create(:campaign, account: account, inbox: inbox)
      contact = create(:contact, account: account, last_activity_at: Time.current)
      create(:contact, account: account, last_activity_at: Time.current)
      matching = create(:conversation, account: account, inbox: inbox, contact: contact, campaign: campaign)
      rule = create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [
                      { 'attribute_key' => 'campaign_id', 'filter_operator' => 'equal_to', 'values' => [campaign.id] }
                    ], schedule: { kind: 'contact_date', date_source: 'last_activity', target_inbox_id: inbox.id })
      cap = instance_double(Automations::ProactiveSendCap, reserve!: true)
      allow(Automations::ProactiveSendCap).to receive(:new).with(account).and_return(cap)
      allow(Redis::Alfred).to receive(:set).and_return(true)

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, matching).once
      expect(AutomationRules::ActionService).to have_received(:new).once
      expect(cap).to have_received(:reserve!).once
      expect(Redis::Alfred).to have_received(:set).once
    end
  end

  describe 'yearly recurrence on a contact attribute (birthday, anniversary)' do
    def birthday_rule(relative_to: 'on', days: nil)
      schedule = {
        'date_source' => 'contact_attribute',
        'attribute_key' => 'cumpleanos',
        'recurrence' => 'yearly',
        'relative_to' => relative_to
      }
      schedule['days'] = days if days
      build_rule(schedule)
    end

    it 'reaches a contact with no conversation by creating one in the target inbox' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact = contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        rule = birthday_rule

        expect(contact.conversations).to be_empty

        described_class.new(rule).perform

        conversation = contact.reload.conversations.last
        expect(conversation).to be_present
        expect(conversation.inbox_id).to eq(inbox.id)
        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation)
      end
    end

    it 'ignores the stored year, matching only month and day' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1974-08-14' })
        described_class.new(birthday_rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'does not fire for a contact whose date is not today' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-15' })
        described_class.new(birthday_rule).perform

        expect(AutomationRules::ActionService).not_to have_received(:new)
      end
    end

    it 'matches N days before the date' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-17' })
        described_class.new(birthday_rule(relative_to: 'before', days: 3)).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'does not fire twice for the same contact in the same year' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        rule = birthday_rule

        described_class.new(rule).perform
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'fires again the following year' do
      contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
      rule = birthday_rule

      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) { described_class.new(rule).perform }
      travel_to(Time.zone.local(2027, 8, 14, 12, 0, 0)) { described_class.new(rule).perform }

      expect(AutomationRules::ActionService).to have_received(:new).twice
    end

    it 'only matches a Feb 29 value in leap years' do
      contact_with(custom_attributes: { 'cumpleanos' => '1992-02-29' })
      rule = birthday_rule

      travel_to(Time.zone.local(2027, 2, 28, 12, 0, 0)) { described_class.new(rule).perform }
      expect(AutomationRules::ActionService).not_to have_received(:new)

      travel_to(Time.zone.local(2028, 2, 29, 12, 0, 0)) { described_class.new(rule).perform }
      expect(AutomationRules::ActionService).to have_received(:new).once
    end

    it 'wraps the year boundary when relative_to is before' do
      travel_to(Time.zone.local(2026, 12, 30, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1990-01-02' })
        described_class.new(birthday_rule(relative_to: 'before', days: 3)).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'uses the account time zone to decide what "today" is' do
      Time.use_zone('America/Guayaquil') do
        # 2026-08-15 00:30 in Guayaquil (UTC-5) is still 2026-08-14 in UTC.
        travel_to(Time.zone.local(2026, 8, 15, 0, 30, 0)) do
          contact_with(custom_attributes: { 'cumpleanos' => '1990-08-15' })
          described_class.new(birthday_rule).perform

          expect(AutomationRules::ActionService).to have_received(:new).once
        end
      end
    end
  end

  describe 'one-shot recurrence on a contact attribute (repurchase, appointment)' do
    it 'fires N days after the stored date, catching up on overdue ones' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'fecha_compra' => '2026-07-15' }) # 30 days
        contact_with(custom_attributes: { 'fecha_compra' => '2026-06-01' }) # long overdue
        contact_with(custom_attributes: { 'fecha_compra' => '2026-08-10' }) # too recent

        rule = build_rule(
          'date_source' => 'contact_attribute', 'attribute_key' => 'fecha_compra',
          'recurrence' => 'once', 'relative_to' => 'after', 'days' => 30
        )
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).twice
      end
    end

    it 'fires N days before the stored date (appointment reminder)' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'fecha_cita' => '2026-08-15' })
        contact_with(custom_attributes: { 'fecha_cita' => '2026-08-20' })

        rule = build_rule(
          'date_source' => 'contact_attribute', 'attribute_key' => 'fecha_cita',
          'recurrence' => 'once', 'relative_to' => 'before', 'days' => 1
        )
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'does not repeat while the date stays the same, but fires again once it moves' do
      contact = contact_with(custom_attributes: { 'fecha_compra' => '2026-07-15' })
      rule = build_rule(
        'date_source' => 'contact_attribute', 'attribute_key' => 'fecha_compra',
        'recurrence' => 'once', 'relative_to' => 'after', 'days' => 30
      )

      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        described_class.new(rule).perform
        described_class.new(rule).perform
        expect(AutomationRules::ActionService).to have_received(:new).once
      end

      # A new purchase moves the date, so the rule is allowed to fire again for it.
      travel_to(Time.zone.local(2026, 9, 20, 12, 0, 0)) do
        contact.update!(custom_attributes: { 'fecha_compra' => '2026-08-21' })
        described_class.new(rule).perform
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end
    end
  end

  describe 'last activity source (win-back)' do
    it 'fires for contacts quiet for N days and skips recent ones' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(last_activity_at: Time.zone.local(2026, 6, 1))  # quiet 74 days
        contact_with(last_activity_at: Time.zone.local(2026, 8, 10)) # quiet 4 days

        rule = build_rule('date_source' => 'last_activity', 'relative_to' => 'after', 'days' => 60)
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
      end
    end

    it 'ignores contacts that never had activity' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(last_activity_at: nil)

        rule = build_rule('date_source' => 'last_activity', 'relative_to' => 'after', 'days' => 60)
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).not_to have_received(:new)
      end
    end
  end

  describe 'send reservations and contact windows' do
    let(:recurrence) { 'once' }
    let(:actions) { [{ 'action_name' => 'send_message', 'action_params' => ['Hola!'] }] }
    let(:rule) do
      create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [], actions: actions, schedule: {
               'kind' => 'contact_date', 'target_inbox_id' => inbox.id,
               'date_source' => 'contact_attribute', 'attribute_key' => 'birthday',
               'recurrence' => recurrence, 'relative_to' => 'on'
             })
    end
    let!(:contact) { create(:contact, account: account, custom_attributes: { 'birthday' => '2026-08-14' }) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:runner) { described_class.new(rule) }
    let(:count_key) do
      format(Redis::RedisKeys::PROACTIVE_SEND_DAILY_COUNT, account_id: account.id, date: Time.zone.today.to_s)
    end
    let(:window_key) { runner.send(:window_key, contact) }

    before { allow(AutomationRules::ActionService).to receive(:new).and_call_original }

    around do |example|
      travel_to(Time.zone.local(2026, 8, 14, 12)) { example.run }
    end

    shared_examples 'an unspent window when conditions do not match' do
      it 'can send on a later run after the condition changes' do
        rule.update!(conditions: [{
                       'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['resolved']
                     }])
        conversation.open!

        runner.perform

        expect(Redis::Alfred.get(window_key)).to be_nil
        expect(Redis::Alfred.get(count_key).to_i).to eq(0)
        expect(conversation.messages.outgoing).to be_empty

        conversation.resolved!
        runner.perform

        expect(conversation.messages.outgoing.count).to eq(1)
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      end
    end

    it_behaves_like 'an unspent window when conditions do not match'

    context 'with yearly recurrence' do
      let(:recurrence) { 'yearly' }

      it_behaves_like 'an unspent window when conditions do not match'
    end

    it 'does not reserve anything when a conversation cannot be resolved' do
      allow(ContactInboxBuilder).to receive(:new).and_raise(StandardError, 'unavailable')

      runner.perform

      expect(Redis::Alfred.get(window_key)).to be_nil
      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(AutomationRules::ActionService).not_to have_received(:new)
    end

    it 'consumes exactly one place even if the actions send two messages' do
      rule.update!(actions: actions * 2)

      runner.perform

      expect(contact.conversations.last.messages.outgoing.count).to eq(2)
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(Redis::Alfred.get(window_key)).to be_present
    end

    it 'releases the second reservation without deleting the first run window' do
      runner.perform
      original_window = Redis::Alfred.get(window_key)
      described_class.new(rule).perform

      expect(contact.conversations.last.messages.outgoing.count).to eq(1)
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(Redis::Alfred.get(window_key)).to eq(original_window)
    end

    it 'does not treat an older outgoing message as a new send' do
      conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Previous')
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['follow-up'] }])

      runner.perform

      expect(conversation.reload.label_list).to include('follow-up')
      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(Redis::Alfred.get(window_key)).to be_nil
    end

    it 'releases a label-only run so the contact can receive a message later' do
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['follow-up'] }])

      runner.perform

      expect(contact.conversations.last.label_list).to include('follow-up')
      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(Redis::Alfred.get(window_key)).to be_nil

      rule.update!(actions: actions)
      described_class.new(rule).perform

      expect(contact.conversations.last.messages.outgoing.count).to eq(1)
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(rule.runs.where(outcome: 'executed').count).to eq(1)
    end

    it 'releases a skipped send without counting its private audit note' do
      allow(runner).to receive(:resolve_conversation).with(contact).and_return(conversation)
      allow(conversation).to receive(:can_reply?).and_return(false)

      runner.perform

      expect(contact.conversations.last.messages.where(private: true)).to exist
      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(Redis::Alfred.get(window_key)).to be_nil
    end

    it 'does not count a private note as an outbound send' do
      rule.update!(actions: [{ 'action_name' => 'add_private_note', 'action_params' => ['Internal only'] }])

      runner.perform

      expect(contact.conversations.last.messages.outgoing.where(private: true).count).to eq(1)
      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(Redis::Alfred.get(window_key)).to be_nil
    end

    it 'does not count an asynchronous webhook as an outbound message' do
      rule.update!(actions: [{ 'action_name' => 'send_webhook_event', 'action_params' => ['https://example.com/hook'] }])

      expect { runner.perform }.to have_enqueued_job(WebhookJob).once

      expect(Redis::Alfred.get(count_key).to_i).to eq(0)
      expect(Redis::Alfred.get(window_key)).to be_nil
    end

    it 'releases a failed action and continues with the next contact' do
      following = create(:contact, account: account, custom_attributes: contact.custom_attributes)
      allow(AutomationRules::ActionService).to receive(:new).with(rule, account, conversation).and_return(action_service)
      allow(action_service).to receive(:perform).and_raise(StandardError, 'send failed')
      allow(Rails.logger).to receive(:error)

      runner.perform

      expect(Redis::Alfred.get(window_key)).to be_nil
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(following.conversations.last.messages.outgoing.count).to eq(1)
      expect(Rails.logger).to have_received(:error).with(
        "[ContactBasedRuleRunner] action failed rule=#{rule.id} contact=#{contact.id}: send failed"
      )

      allow(AutomationRules::ActionService).to receive(:new).and_call_original
      described_class.new(rule).perform

      expect(conversation.messages.outgoing.count).to eq(1)
      expect(Redis::Alfred.get(count_key).to_i).to eq(2)
    end

    it 'pauses at the cap without claiming windows for remaining contacts' do
      account.update!(settings: { 'proactive_daily_send_cap' => 1 })
      following = create(:contact, account: account, custom_attributes: contact.custom_attributes)

      runner.perform

      expect(rule.reload.active?).to be(false)
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(Redis::Alfred.get(runner.send(:window_key, following))).to be_nil
      expect(following.conversations.last.messages.outgoing).to be_empty
    end

    it 'retains the reservation and window for a deferred message' do
      rule.update!(actions: [actions.first.merge('delivery' => { 'delay_seconds' => 5 })])

      expect { runner.perform }.to have_enqueued_job(Messages::DeferredOutboundJob).once
      described_class.new(rule).perform

      expect(contact.conversations.last.messages.outgoing).to be_empty
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(Redis::Alfred.get(window_key)).to be_present
    end

    it 'retains the reservation and window for a deferred attachment' do
      # Deliberately skips validation: the blobs are attached right after.
      rule.update_columns(actions: [{ # rubocop:disable Rails/SkipsModelValidations
                            'action_name' => 'send_attachment', 'action_params' => [],
                            'delivery' => { 'delay_seconds' => 5 }
                          }])
      rule.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      rule.update!(actions: [rule.actions.first.merge('action_params' => rule.files.blobs.ids)])

      expect { runner.perform }.to have_enqueued_job(Messages::DeferredOutboundJob).once
      described_class.new(rule).perform

      expect(contact.conversations.last.messages.outgoing).to be_empty
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      expect(Redis::Alfred.get(window_key)).to be_present
    end

    %w[execute_macro enter_flow send_email_transcript].each do |action_name|
      it "conservatively retains reservations for #{action_name} even when it skips" do
        rule.update_columns( # rubocop:disable Rails/SkipsModelValidations
          actions: [{ 'action_name' => action_name, 'action_params' => [] }]
        )
        allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)

        runner.perform
        described_class.new(rule).perform

        expect(action_service).to have_received(:perform).once
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
        expect(Redis::Alfred.get(window_key)).to be_present
      end
    end

    it 'keeps candidate counts read-only before and after sending' do
      expect(runner.candidates_count).to eq(1)
      expect(Redis::Alfred.get(count_key)).to be_nil
      expect(contact.conversations).to be_empty

      runner.perform

      expect(described_class.new(rule).candidates_count).to eq(1)
      expect(Redis::Alfred.get(count_key).to_i).to eq(1)
    end

    context 'with WhatsApp Cloud' do
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                  sync_templates: false, validate_provider_config: false)
      end
      let(:inbox) { channel.inbox }

      before { allow(Rails.logger).to receive(:info) }

      it 'skips free text at exactly 24 hours and releases both reservations' do
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 24.hours.ago)

        runner.perform

        expect(conversation.messages.outgoing).to be_empty
        expect(AutomationRules::ActionService).not_to have_received(:new)
        expect(Redis::Alfred.get(count_key).to_i).to eq(0)
        expect(Redis::Alfred.get(window_key)).to be_nil
        expect(Rails.logger).to have_received(:info).with(
          "[ContactBasedRuleRunner] skipped rule=#{rule.id} contact=#{contact.id} reason=window_closed_needs_template"
        )
      end

      it 'releases a delayed free text send without enqueuing it' do
        rule.update!(actions: [actions.first.merge('delivery' => { 'delay_seconds' => 5 })])
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)

        expect { runner.perform }.not_to have_enqueued_job(Messages::DeferredOutboundJob)

        expect(Redis::Alfred.get(count_key).to_i).to eq(0)
        expect(Redis::Alfred.get(window_key)).to be_nil
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end

      it 'can send on a subsequent scan after a new incoming message opens the window' do
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)
        runner.perform
        create(:message, account: account, conversation: conversation, message_type: :incoming)

        described_class.new(rule).perform

        expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
        expect(Redis::Alfred.get(window_key)).to be_present
      end

      it 'skips a new conversation without an incoming message' do
        contact.update!(phone_number: '+593990000001') # a WhatsApp contact inbox needs a phone number
        runner.perform

        expect(contact.conversations.sole.messages.outgoing).to be_empty
        expect(Redis::Alfred.get(count_key).to_i).to eq(0)
        expect(Redis::Alfred.get(window_key)).to be_nil
      end

      it 'sends free text within the window' do
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 23.hours.ago)

        runner.perform

        expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
        expect(Redis::Alfred.get(window_key)).to be_present
      end

      it 'sends an approved template outside the window' do
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)
        rule.update!(actions: [{ 'action_name' => 'send_whatsapp_template', 'action_params' => [{
                       'inbox_id' => inbox.id, 'name' => 'sample_shipping_confirmation', 'language' => 'en_US',
                       'processed_params' => { 'body' => { '1' => '3' } }
                     }] }])

        runner.perform

        message = conversation.messages.outgoing.where(private: false).sole
        expect(message.additional_attributes.dig('template_params', 'name')).to eq('sample_shipping_confirmation')
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
        expect(Redis::Alfred.get(window_key)).to be_present
      end

      it 'keeps the existing window when a repeat scan is skipped' do
        create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 23.hours.ago)
        runner.perform
        original_window = Redis::Alfred.get(window_key)

        travel 2.hours
        described_class.new(rule).perform

        expect(Redis::Alfred.get(window_key)).to eq(original_window)
        expect(Redis::Alfred.get(count_key).to_i).to eq(1)
      end

      context 'with the default WhatsApp provider' do
        let(:channel) do
          create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
        end

        it 'leaves the existing action service window handling in place' do
          create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)

          runner.perform

          expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation)
          expect(conversation.messages.where(private: true)).to exist
          expect(Redis::Alfred.get(count_key).to_i).to eq(0)
          expect(Redis::Alfred.get(window_key)).to be_nil
        end
      end
    end
  end

  describe '#candidates_breakdown' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false)
    end
    let(:inbox) { channel.inbox }
    let(:rule) do
      build(:automation_rule, account: account, schedule: {
              'kind' => 'contact_date', 'target_inbox_id' => inbox.id,
              'attribute_key' => 'birthday', 'test_mode_label' => 'test'
            })
    end
    let(:runner) { described_class.new(rule) }
    let(:birthday) { { 'birthday' => '2026-08-14' } }

    around do |example|
      travel_to(Time.zone.local(2026, 8, 14, 12)) { example.run }
    end

    it 'counts candidates, existing windows and test exclusions without writing' do
      open_contact = create(:contact, account: account, custom_attributes: birthday)
      open_contact.update!(label_list: ['test'])
      open_conversation = create(:conversation, account: account, inbox: inbox, contact: open_contact)
      create(:message, account: account, conversation: open_conversation, message_type: :incoming, created_at: 23.hours.ago)
      closed_contact = create(:contact, account: account, custom_attributes: birthday)
      closed_conversation = create(:conversation, account: account, inbox: inbox, contact: closed_contact)
      create(:message, account: account, conversation: closed_conversation, message_type: :incoming, created_at: 24.hours.ago)
      create(:contact, account: account, custom_attributes: birthday)
      create(:contact, custom_attributes: birthday)

      expect { runner.candidates_breakdown }.not_to change(Conversation, :count)
      expect(runner.candidates_count).to eq(3)
      expect(runner.candidates_breakdown).to eq(
        candidates: 3, with_open_window: 1, window_closed: 1, excluded_by_test_mode: 2
      )
      expect(AutomationRules::ActionService).not_to have_received(:new)
    end

    it 'uses the latest conversation in the target inbox' do
      contact = create(:contact, account: account, custom_attributes: birthday)
      older = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago)
      create(:message, account: account, conversation: older, message_type: :incoming, created_at: 1.hour.ago)
      create(:conversation, account: account, inbox: inbox, contact: contact)

      expect(runner.candidates_breakdown).to include(with_open_window: 0, window_closed: 1)
    end

    it 'returns zero diagnostics for an incomplete schedule' do
      rule.schedule = { 'kind' => 'contact_date' }

      expect(runner.candidates_count).to eq(0)
      expect(runner.candidates_breakdown).to eq(
        candidates: 0, with_open_window: 0, window_closed: 0, excluded_by_test_mode: 0
      )
    end

    context 'with another channel' do
      let(:inbox) { create(:inbox, account: account) }

      it 'does not classify its conversations as WhatsApp windows' do
        contact = create(:contact, account: account, custom_attributes: birthday)
        create(:conversation, account: account, inbox: inbox, contact: contact)

        expect(runner.candidates_breakdown).to eq(
          candidates: 1, with_open_window: 0, window_closed: 0, excluded_by_test_mode: 1
        )
      end
    end
  end

  describe 'safety rails' do
    it 'skips contacts without the test_mode_label when one is configured' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        tagged = contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        tagged.update!(label_list: ['beta-proactivo'])

        rule = build_rule(
          'date_source' => 'contact_attribute', 'attribute_key' => 'cumpleanos',
          'recurrence' => 'yearly', 'relative_to' => 'on', 'test_mode_label' => 'beta-proactivo'
        )
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, tagged.reload.conversations.last)
      end
    end

    it 'pauses the rule and stops once the account daily send cap is reached' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        account.update!(settings: (account.settings || {}).merge('proactive_daily_send_cap' => 1))
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })

        rule = build_rule(
          'date_source' => 'contact_attribute', 'attribute_key' => 'cumpleanos',
          'recurrence' => 'yearly', 'relative_to' => 'on'
        )
        described_class.new(rule).perform

        expect(AutomationRules::ActionService).to have_received(:new).once
        expect(rule.reload.active).to be(false)
      end
    end

    it 'reuses an existing conversation in the target inbox instead of creating another' do
      travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) do
        contact = contact_with(custom_attributes: { 'cumpleanos' => '1990-08-14' })
        existing = create(:conversation, account: account, inbox: inbox, contact: contact)

        rule = build_rule(
          'date_source' => 'contact_attribute', 'attribute_key' => 'cumpleanos',
          'recurrence' => 'yearly', 'relative_to' => 'on'
        )
        described_class.new(rule).perform

        expect(contact.reload.conversations.count).to eq(1)
        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, existing)
      end
    end

    it 'does nothing for a conversation-scoped schedule kind' do
      rule = create(
        :automation_rule,
        account: account,
        event_name: 'time_triggered',
        conditions: [],
        actions: [{ 'action_name' => 'add_label', 'action_params' => ['seguimiento'] }],
        schedule: { 'kind' => 'days_since_attribute', 'attribute_key' => 'fecha_cita', 'relative_to' => 'on' }
      )

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).not_to have_received(:new)
    end
  end

  describe 'execution history' do
    let!(:history_contact) { create(:contact, account: account, last_activity_at: Time.current) }
    let(:history_conversation) { create(:conversation, account: account, inbox: inbox, contact: history_contact) }
    let(:history_rule) do
      create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [],
                               actions: [{ 'action_name' => 'add_label', 'action_params' => ['history'] }],
                               schedule: { kind: 'contact_date', target_inbox_id: inbox.id, date_source: 'last_activity' })
    end
    let(:runner) { described_class.new(history_rule) }
    let(:send_cap) { instance_double(Automations::ProactiveSendCap, reserve!: true, release!: true) }

    before do
      allow(AutomationRules::ActionService).to receive(:new).and_call_original
      allow(runner).to receive(:resolve_conversation).and_return(history_conversation)
      allow(runner).to receive(:cap).and_return(send_cap)
    end

    it 'records the cap omission and preserves the pause' do
      allow(send_cap).to receive(:reserve!).and_return(false)
      runner.perform

      expect(history_rule.runs.sole).to have_attributes(outcome: 'skipped', reason: 'cap_reached')
      expect(history_rule.reload.active).to be(false)
    end

    it 'records a consumed window and releases the cap' do
      allow(runner).to receive(:claim_window!).and_return(false)
      runner.perform

      expect(history_rule.runs.sole.reason).to eq('window_consumed')
      expect(send_cap).to have_received(:release!)
    end

    it 'records no message created once and releases both reservations' do
      allow(runner).to receive(:claim_window!).and_return(true)
      allow(runner).to receive(:release_window!)
      runner.perform

      expect(history_rule.runs.sole).to have_attributes(outcome: 'skipped', reason: 'no_send_created')
      expect(history_rule.runs.sole.details['actions']).to eq([{ 'name' => 'add_label', 'outcome' => 'ok' }])
      expect(send_cap).to have_received(:release!)
      expect(runner).to have_received(:release_window!).with(history_contact)
    end

    it 'records a failed action once while releasing the reservations' do
      allow(runner).to receive(:claim_window!).and_return(true)
      allow(runner).to receive(:release_window!)
      service = AutomationRules::ActionService.new(history_rule, account, history_conversation)
      allow(AutomationRules::ActionService).to receive(:new).and_return(service)
      allow(service).to receive(:execute_action).and_raise(ArgumentError, 'private data')
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
      runner.perform

      expect(history_rule.runs.sole).to have_attributes(outcome: 'failed', reason: 'action_error')
      expect(history_rule.runs.sole.details.to_json).not_to include('private data')
      expect(send_cap).to have_received(:release!)
    end
  end
end
