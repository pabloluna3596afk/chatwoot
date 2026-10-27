require 'rails_helper'

class RegisteredCopilotTestAction
  class << self
    attr_accessor :executions

    def action_name = 'registered_test_action'
    def schema = { type: 'object', additionalProperties: false }
  end

  def initialize(**); end
  def validate; end
  def preview = { action: self.class.action_name }
  def required_permission = 'conversation_manage'

  def execute
    self.class.executions = self.class.executions.to_i + 1
    { code: 'test_executed' }
  end
end

RSpec.describe Captain::Copilot::ActionItemService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
  let(:service) { described_class.new(thread: thread, user: user) }

  before do
    Captain::Copilot::ActionRegistry.register(RegisteredCopilotTestAction)
    RegisteredCopilotTestAction.executions = 0
  end

  after do
    Captain::Copilot::ActionRegistry.unregister(RegisteredCopilotTestAction)
  end

  it 'registers an action without changing the proposal engine and waits for approval to execute' do
    item = service.propose(
      action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
      payload: {}, turn_count: 1
    )

    expect(item).to be_pending
    expect(item.events.pluck(:event)).to eq(['proposed'])
    expect(RegisteredCopilotTestAction.executions).to eq(0)

    service.decide(item: item, decision: 'approve')
    service.decide(item: item, decision: 'approve')

    expect(item.reload.status).to eq('executed')
    expect(RegisteredCopilotTestAction.executions).to eq(1)
    expect(item.events.pluck(:event)).to eq(%w[proposed approved executed])
  end

  it 'rejects edits once the proposal has been decided' do
    item = service.propose(
      action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
      payload: {}, turn_count: 1
    )
    service.decide(item: item, decision: 'reject')

    expect { service.update(item: item, payload: { changed: true }) }.to raise_error(ArgumentError)
  end

  it 'revalidates an edit and replaces the payload hash' do
    item = service.propose(
      action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
      payload: { original: true }, turn_count: 1
    )
    original_hash = item.payload_hash

    service.update(item: item, payload: { changed: true })

    expect(item.reload.status).to eq('pending')
    expect(item.payload_hash).not_to eq(original_hash)
    expect(item.events.pluck(:event)).to eq(%w[proposed edited])
  end

  it 'limits the number of pending proposals in a thread' do
    5.times do
      service.propose(
        action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
        payload: {}, turn_count: 1
      )
    end

    expect do
      service.propose(
        action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
        payload: {}, turn_count: 1
      )
    end.to raise_error(ArgumentError, 'At most five proposals may be pending in this thread')
  end

  it 'rejects a fourth proposal in the same turn' do
    expect do
      service.propose(
        action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
        payload: {}, turn_count: 4
      )
    end.to raise_error(ArgumentError, 'At most three proposals are allowed per turn')
  end

  it 'expires a proposal before executing it after 24 hours' do
    item = service.propose(
      action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
      payload: {}, turn_count: 1
    )

    travel_to(25.hours.from_now) do
      service.decide(item: item, decision: 'approve')
    end

    expect(item.reload.status).to eq('expired')
    expect(RegisteredCopilotTestAction.executions).to eq(0)
    expect(item.events.pluck(:event)).to eq(%w[proposed expired])
  end

  it 'keeps audit events append-only' do
    item = service.propose(
      action_name: 'registered_test_action', target_type: 'Conversation', target_id: 42,
      payload: {}, turn_count: 1
    )

    expect { item.events.first.update!(metadata: { changed: true }) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { item.events.first.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
