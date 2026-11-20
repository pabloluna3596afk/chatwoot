require 'rails_helper'

RSpec.describe ActivityMessageHandler do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, name: 'Pablo Luna') }
  let(:assignee) { create(:user, account: account, name: 'Ana Ruiz') }
  let(:conversation) { create(:conversation, account: account, status: :open) }
  let(:payloads) { [] }

  before do
    conversation
    Current.user = actor
    allow(Conversations::ActivityMessageJob).to receive(:perform_later) { |_record, params, *_rest| payloads << params }
  end

  after { Current.reset }

  shared_examples 'an activity with literal names' do
    it 'persists only the interpolated names, uniquely and in text order' do
      instance_exec(&action)
      expect(payloads).not_to be_empty
      payload = payloads.last
      names = payload.dig(:content_attributes, :activity, :names)
      expect(names).to eq(expected_names)
      names.each { |name| expect(payload[:content]).to include(name) }
      expect(names.map { |name| payload[:content].index(name) }).to eq(names.map { |name| payload[:content].index(name) }.sort)
    end
  end

  %w[resolved pending snoozed].each do |status|
    context "when a human changes status to #{status}" do
      let(:action) { -> { conversation.update!(status: status) } }
      let(:expected_names) { [actor.name] }

      it_behaves_like 'an activity with literal names'
    end
  end

  context 'when a human reopens' do
    let(:action) do
      lambda do
        conversation.update!(status: :resolved)
        conversation.update!(status: :open)
      end
    end
    let(:expected_names) { [actor.name] }

    it_behaves_like 'an activity with literal names'
  end

  context 'when a contact resolves with the existing capitalization' do
    let(:action) do
      lambda do
        Current.user = nil
        Current.contact = conversation.contact
        conversation.resolved!
      end
    end
    let(:expected_names) { [conversation.contact.name.capitalize] }

    it_behaves_like 'an activity with literal names'
  end

  context 'when an agent assigns another person' do
    let(:action) { -> { conversation.send(:create_assignee_change_activity, actor.name) } }
    let(:expected_names) { [assignee.name, actor.name] }

    before { conversation.assignee = assignee }

    it_behaves_like 'an activity with literal names'
  end

  context 'when an agent assigns themself' do
    let(:action) { -> { conversation.send(:create_assignee_change_activity, actor.name) } }
    let(:expected_names) { [actor.name] }

    before { conversation.assignee = actor }

    it_behaves_like 'an activity with literal names'
  end

  context 'when an agent unassigns' do
    let(:action) { -> { conversation.send(:create_assignee_change_activity, actor.name) } }
    let(:expected_names) { [actor.name] }

    it_behaves_like 'an activity with literal names'
  end

  %w[added removed].each do |change|
    context "when labels are #{change}" do
      let(:action) { -> { conversation.send(:create_label_change_activity, change, actor.name, %w[VIP Soporte VIP]) } }
      let(:expected_names) { [actor.name, 'VIP', 'Soporte'] }

      it_behaves_like 'an activity with literal names'
    end
  end

  [[nil, 'high'], %w[high urgent], ['urgent', nil]].each do |old_priority, new_priority|
    context "when priority changes from #{old_priority.inspect} to #{new_priority.inspect}" do
      let(:action) do
        -> { conversation.send(:priority_change_activity, actor.name) }
      end
      let(:expected_names) { [actor.name] }

      before { allow(conversation).to receive(:previous_changes).and_return('priority' => [old_priority, new_priority]) }

      it_behaves_like 'an activity with literal names'
    end
  end

  %w[added removed].each do |change|
    context "when an SLA is #{change}" do
      let(:action) { -> { conversation.send(:create_sla_change_activity, change, actor.name) } }
      let(:expected_names) { [actor.name, 'VIP SLA'] }

      before do
        allow(conversation).to receive(:sla_policy_name).and_return('VIP SLA')
      end

      it_behaves_like 'an activity with literal names'
    end
  end

  %w[muted unmuted].each do |change|
    context "when a conversation is #{change}" do
      let(:action) { -> { conversation.send(:create_mute_change_activity, change) } }
      let(:expected_names) { [actor.name] }

      it_behaves_like 'an activity with literal names'
    end
  end

  context 'when an assignment policy acts' do
    let(:policy) { create(:assignment_policy, account: account, name: 'Ventas Round Robin') }
    let(:action) { -> { conversation.send(:create_assignee_change_activity, nil) } }
    let(:expected_names) { [assignee.name, policy.name] }

    before do
      Current.user = nil
      Current.executed_by = policy
      conversation.assignee = assignee
    end

    it_behaves_like 'an activity with literal names'
  end

  context 'when an automation changes status' do
    let(:rule) { create(:automation_rule, account: account, name: 'Cerrar VIP') }
    let(:action) do
      lambda do
        Current.user = nil
        Current.executed_by = rule
        conversation.resolved!
      end
    end
    let(:expected_names) { [rule.name] }

    it_behaves_like 'an activity with literal names'
  end

  context 'when the default assignment policy acts' do
    let(:action) { -> { conversation.send(:create_assignee_change_activity, nil) } }
    let(:expected_names) { [assignee.name, I18n.t('auto_assignment.default_policy_name')] }

    before do
      Current.user = nil
      Current.executed_by = conversation.inbox
      conversation.assignee = assignee
    end

    it_behaves_like 'an activity with literal names'
  end

  context 'when an account uses Spanish' do
    let(:action) { -> { conversation.resolved! } }
    let(:expected_names) { [actor.name] }

    before { account.update!(locale: 'es') }

    it_behaves_like 'an activity with literal names'
  end

  it 'does not add names to system-only activities' do
    Current.reset
    conversation.resolved!
    expect(payloads.last.dig(:content_attributes, :activity)).not_to have_key(:names)
  end

  it 'does not attribute an incoming-message system reopen to the authenticated agent' do
    conversation.resolved!
    Current.executed_by = conversation.contact
    conversation.open!

    expect(payloads.last[:content]).to eq(I18n.t('conversations.activity.status.system_auto_open'))
    expect(payloads.last.dig(:content_attributes, :activity)).not_to have_key(:names)
  end

  it 'leaves legacy job payloads valid' do
    params = { account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, content: 'Historical activity' }
    Conversations::ActivityMessageJob.new.perform(conversation, params)
    expect(conversation.messages.last.content_attributes).not_to have_key('activity')
  end

  it 'exposes the same names in message events and webhooks without adding private data' do
    conversation.resolved!
    Conversations::ActivityMessageJob.new.perform(conversation, payloads.last)
    message = conversation.messages.activity.last

    expect(message.push_event_data[:content_attributes].dig('activity', 'names')).to eq([actor.name])
    expect(message.webhook_data[:content_attributes].dig('activity', 'names')).to eq([actor.name])
    expect(message.content).to include(actor.name)
  end
end
