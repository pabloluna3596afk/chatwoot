# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Automations::TimeBasedRuleRunner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: true) }

  def conversation_on(date, extras = {})
    create(
      :conversation,
      account: account,
      inbox: inbox,
      custom_attributes: { 'fecha_cita' => date.iso8601 }.merge(extras)
    )
  end

  def build_rule(relative_to:, days: nil)
    attrs = {
      account: account,
      event_name: 'time_triggered',
      conditions: [],
      actions: [{ 'action_name' => 'add_label', 'action_params' => ['seguimiento'] }],
      schedule: {
        'kind' => 'days_since_attribute',
        'attribute_key' => 'fecha_cita',
        'relative_to' => relative_to
      }
    }
    attrs[:schedule]['days'] = days unless days.nil?
    create(:automation_rule, attrs)
  end

  before do
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
  end

  around do |example|
    Time.use_zone('UTC') { travel_to(Time.zone.local(2026, 8, 14, 12, 0, 0)) { example.run } }
  end

  describe '#perform with a campaign condition' do
    it 'filters candidates before claiming their time window' do
      campaign = create(:campaign, account: account, inbox: inbox)
      matching = create(:conversation, account: account, inbox: inbox, campaign: campaign,
                                        custom_attributes: { 'fecha_cita' => Time.zone.today.iso8601 })
      create(:conversation, account: account, inbox: inbox, custom_attributes: { 'fecha_cita' => Time.zone.today.iso8601 })
      rule = create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [
                      { 'attribute_key' => 'campaign_id', 'filter_operator' => 'equal_to', 'values' => [campaign.id] }
                    ], schedule: { kind: 'days_since_attribute', attribute_key: 'fecha_cita', relative_to: 'on' })
      allow(Redis::Alfred).to receive(:set).and_return(true)

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, matching).once
      expect(AutomationRules::ActionService).to have_received(:new).once
      expect(Redis::Alfred).to have_received(:set).once
    end
  end

  describe '#perform with days_since_attribute' do
    it 'matches dates on or before today minus N when relative_to is after' do
      matching = conversation_on(Date.new(2026, 8, 13))
      older = conversation_on(Date.new(2026, 8, 10))
      today_convo = conversation_on(Date.new(2026, 8, 14))
      tomorrow = conversation_on(Date.new(2026, 8, 15))
      rule = build_rule(relative_to: 'after', days: 1)

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, matching)
      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, older)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, today_convo)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, tomorrow)
    end

    it 'matches only today when relative_to is on' do
      today_convo = conversation_on(Date.new(2026, 8, 14))
      yesterday = conversation_on(Date.new(2026, 8, 13))
      tomorrow = conversation_on(Date.new(2026, 8, 15))
      rule = build_rule(relative_to: 'on')

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, today_convo)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, yesterday)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, tomorrow)
    end

    it 'matches today plus N when relative_to is before' do
      in_three_days = conversation_on(Date.new(2026, 8, 17))
      today_convo = conversation_on(Date.new(2026, 8, 14))
      in_two_days = conversation_on(Date.new(2026, 8, 16))
      rule = build_rule(relative_to: 'before', days: 3)

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, in_three_days)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, today_convo)
      expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, in_two_days)
    end

    it 'does not fire after when days is 0' do
      conversation_on(Date.new(2026, 8, 14))
      rule = build(:automation_rule, account: account, event_name: 'time_triggered', conditions: [],
                                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['seguimiento'] }],
                                     schedule: {
                                       'kind' => 'days_since_attribute',
                                       'attribute_key' => 'fecha_cita',
                                       'relative_to' => 'after',
                                       'days' => 0
                                     })
      rule.schedule['days'] = 1
      rule.save!
      rule.update_columns(schedule: rule.schedule.merge('days' => 0)) # rubocop:disable Rails/SkipsModelValidations

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).not_to have_received(:new)
    end

    it 'treats missing relative_to as after' do
      matching = conversation_on(Date.new(2026, 8, 13))
      rule = create(
        :automation_rule,
        account: account,
        event_name: 'time_triggered',
        conditions: [],
        actions: [{ 'action_name' => 'add_label', 'action_params' => ['seguimiento'] }],
        schedule: {
          'kind' => 'days_since_attribute',
          'attribute_key' => 'fecha_cita',
          'days' => 1
        }
      )

      described_class.new(rule).perform

      expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, matching)
    end
  end
end
