require 'rails_helper'

RSpec.describe AutomationRules::ContactUpdatedService do
  subject(:service) { described_class.new(rule, contact, changes) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { interest: 'Interesado' }) }
  let!(:definition) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_display_type: 'text', attribute_key: 'interest')
  end
  let(:condition) do
    { 'attribute_key' => definition.attribute_key, 'custom_attribute_type' => 'contact_attribute',
      'filter_operator' => 'equal_to', 'values' => ['Interesado'], 'query_operator' => nil }
  end
  let(:changes) { { 'custom_attributes' => [{ 'interest' => 'Nuevo' }, { 'interest' => 'Interesado' }] } }
  let!(:rule) do
    create(:automation_rule, account: account, event_name: 'contact_updated', conditions: [condition],
                             actions: [{ action_name: 'change_priority', action_params: ['high'] }])
  end
  let!(:conversation) { create(:conversation, account: account, contact: contact, status: :open) }

  before do
    allow(AutomationRules::ActionService).to receive(:new).and_call_original
  end

  it 'saves the event and executes on the latest open or pending conversation' do
    older = create(:conversation, account: account, contact: contact, status: :open, created_at: 2.days.ago)
    latest = create(:conversation, account: account, contact: contact, status: :pending, created_at: 1.hour.from_now)
    create(:conversation, account: account, contact: contact, status: :resolved, created_at: 2.hours.from_now)
    create(:conversation, account: account, contact: contact, status: :snoozed, created_at: 3.hours.from_now)

    service.perform

    expect(rule.reload.event_name).to eq('contact_updated')
    expect(latest.reload.priority).to eq('high')
    expect(older.reload.priority).to be_nil
    expect(conversation.reload.priority).to be_nil
  end

  it 'logs and does not create a conversation when none is open or pending' do
    conversation.update!(status: :resolved)
    allow(Rails.logger).to receive(:info)

    expect { service.perform }.not_to change(Conversation, :count)

    expect(AutomationRules::ActionService).not_to have_received(:new)
    expect(Rails.logger).to have_received(:info).with(%r{no open/pending conversation})
  end

  it 'does nothing when the conditions do not match' do
    contact.update!(custom_attributes: { interest: 'Otro' })

    service.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
    expect(rule.reload.active).to be(true)
  end

  it 'deduplicates the same change even with different timestamps and hash key order' do
    changes['email'] = %w[old@example.com new@example.com]
    changes['updated_at'] = [1.minute.ago, Time.current]
    service.perform
    repeated = changes.merge('updated_at' => [Time.current, 1.minute.from_now]).to_a.reverse.to_h
    described_class.new(rule, contact, repeated).perform

    expect(AutomationRules::ActionService).to have_received(:new).once
  end

  it 'executes once when the contact is saved twice with the same attribute value' do
    contact.update!(custom_attributes: { interest: 'Nuevo' })
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, name, timestamp, data|
      AutomationRuleListener.instance.contact_updated(Events::Base.new(name, timestamp, data)) if name == 'contact.updated'
      original.call(name, timestamp, data)
    end

    2.times { contact.update!(custom_attributes: { interest: 'Interesado' }) }

    expect(AutomationRules::ActionService).to have_received(:new).once
  end

  it 'sets a ten-minute expiration on the deduplication claim' do
    service.perform
    ttl = Redis::Alfred.ttl(service.send(:dedupe_key))

    expect(ttl).to be_between(590, 600)
  end

  it 'does not consume daily capacity for duplicate changes or nonmatching conditions' do
    key = "automation:contact_updated:daily:#{account.id}:#{Time.zone.today}"
    service.perform
    service.perform
    contact.update!(custom_attributes: { interest: 'Otro' })
    described_class.new(rule, contact, 'custom_attributes' => [{}, { interest: 'Otro' }]).perform

    expect(Redis::Alfred.get(key).to_i).to eq(1)
  end

  it 'restricts the target inbox before choosing the latest conversation' do
    rule.update!(conditions: [condition.merge('query_operator' => 'AND'),
                              { attribute_key: 'inbox_id', filter_operator: 'equal_to',
                                values: [conversation.inbox_id], query_operator: nil }])
    other = create(:conversation, account: account, contact: contact, status: :open, created_at: 1.hour.from_now)

    service.perform

    expect(conversation.reload.priority).to eq('high')
    expect(other.reload.priority).to be_nil
  end

  it 'does not fall back to another inbox when the selected inbox has no eligible conversation' do
    rule.update!(conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to',
                                values: [conversation.inbox_id], query_operator: nil }])
    conversation.update!(status: :resolved)
    create(:conversation, account: account, contact: contact, status: :open)

    service.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  it 'supports attribute_changed on a contact custom attribute using previous_changes' do
    rule.update!(conditions: [condition.merge('filter_operator' => 'attribute_changed',
                                              'values' => { 'from' => ['Nuevo'], 'to' => ['Interesado'] })])

    service.perform

    expect(conversation.reload.priority).to eq('high')
  end

  it 'supports standard contact attribute changes' do
    rule.update!(conditions: [{ attribute_key: 'email', filter_operator: 'attribute_changed',
                                values: { from: ['old@example.com'], to: ['new@example.com'] }, query_operator: nil }])

    described_class.new(rule, contact, 'email' => %w[old@example.com new@example.com]).perform

    expect(conversation.reload.priority).to eq('high')
  end

  it 'ignores saves containing only bookkeeping changes' do
    described_class.new(rule, contact, 'updated_at' => [1.minute.ago, Time.current]).perform
    described_class.new(rule, contact, {}).perform
    described_class.new(rule, contact, 'additional_attributes' => [{}, { 'avatar_url' => 'https://example.com/avatar' }]).perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  it 'enforces 200 executions per account and calendar day independently of proactive send settings' do
    account.update!(settings: { 'proactive_daily_send_cap' => 1000 })
    key = "automation:contact_updated:daily:#{account.id}:#{Time.zone.today}"
    Redis::Alfred.set(key, 199, ex: 2.days.to_i)

    service.perform
    described_class.new(rule, contact, 'email' => %w[a@example.com b@example.com]).perform

    expect(AutomationRules::ActionService).to have_received(:new).once
    travel 1.day do
      described_class.new(rule, contact, 'email' => %w[b@example.com c@example.com]).perform
    end
    expect(AutomationRules::ActionService).to have_received(:new).twice
  end

  it 'keeps separate quotas for different accounts' do
    Redis::Alfred.set("automation:contact_updated:daily:#{create(:account).id}:#{Time.zone.today}", 200, ex: 2.days.to_i)

    service.perform

    expect(conversation.reload.priority).to eq('high')
  end

  it 'does not allow delayed contact rules' do
    rule.execution_delay = 10

    expect(rule).not_to be_valid
    expect(rule.errors[:execution_delay]).to include('cannot be used with contact_updated events.')
  end

  it 'does not simulate the contact event or touch execution ledgers' do
    simulation = AutomationRules::SimulationService.new(account: account, conversation: conversation, event_name: 'contact_updated')
    allow(Redis::Alfred).to receive(:set).and_call_original
    allow(Redis::Alfred).to receive(:incr).and_call_original

    expect(simulation.perform.evaluated_count).to eq(0)
    expect(simulation.perform.matches).to be_empty
    expect(AutomationRules::ActionService).not_to have_received(:new)
    expect(Redis::Alfred).not_to have_received(:set)
    expect(Redis::Alfred).not_to have_received(:incr)
  end

  it 'dispatches the action actor and prevents another contact rule from running after Current resets' do
    rule.update!(actions: [{ action_name: 'update_contact_custom_attribute',
                             action_params: [{ attribute_key: 'interest', value: 'Seguimiento' }] }])
    create(:automation_rule, account: account, event_name: 'contact_updated',
                             conditions: [condition.merge('values' => ['Seguimiento'])],
                             actions: [{ action_name: 'change_priority', action_params: ['urgent'] }])
    dispatched = []
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, name, timestamp, data|
      dispatched << Events::Base.new(name, timestamp, data) if name == 'contact.updated'
      original.call(name, timestamp, data)
    end

    service.perform

    expect(contact.reload.custom_attributes['interest']).to eq('Seguimiento')
    expect(dispatched.size).to eq(1)
    expect(dispatched.first.data[:performed_by]).to eq(rule)
    expect(Current.executed_by).to be_nil
    AutomationRuleListener.instance.contact_updated(dispatched.first)
    expect(conversation.reload.priority).to be_nil
    expect(AutomationRules::ActionService).to have_received(:new).once
  end

  it 'runs active account rules in ascending ID order through the listener' do
    second = create(:automation_rule, account: account, event_name: 'contact_updated', conditions: [condition],
                                      actions: [{ action_name: 'change_priority', action_params: ['urgent'] }])
    create(:automation_rule, account: account, event_name: 'contact_updated', conditions: [condition], active: false)
    event = Events::Base.new('contact.updated', Time.current, contact: contact, changed_attributes: changes)

    expect(AutomationRules::ActionService).to receive(:new).with(rule, account, conversation).ordered.and_call_original
    expect(AutomationRules::ActionService).to receive(:new).with(second, account, conversation).ordered.and_call_original
    AutomationRuleListener.instance.contact_updated(event)

    expect(conversation.reload.priority).to eq('urgent')
  end
end
