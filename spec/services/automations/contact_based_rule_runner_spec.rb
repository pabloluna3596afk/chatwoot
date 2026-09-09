# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Automations::ContactBasedRuleRunner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: true) }

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
      actions: [{ 'action_name' => 'send_message', 'action_params' => { message: 'Hola!' } }],
      schedule: schedule
    )
  end

  before do
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
  end

  around do |example|
    Time.use_zone('UTC') { example.run }
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
end
