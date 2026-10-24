require 'rails_helper'

RSpec.describe InternalTasks::AutomatedCreateService do
  subject(:service) { described_class.new(conversation: conversation, source: rule, params: params) }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: agent) }
  let(:rule) { create(:automation_rule, account: account) }
  let(:params) { [{ 'title' => 'Call the customer' }] }

  before { account.enable_features!('internal_tasks') }

  after { Current.reset }

  it 'links the conversation and contact and defaults to the conversation assignee' do
    task = service.perform

    expect(task.conversation).to eq(conversation)
    expect(task.conversation.contact).to eq(conversation.contact)
    expect(task.assigned_to).to eq(agent)
    expect(task.title).to eq('Call the customer')
    expect(task.due_at).to be_nil
  end

  it 'records system authorship without impersonating the current user' do
    Current.user = agent
    task = service.perform

    expect(task.created_by).to be_nil
    expect(task.metadata).to include('created_by_type' => 'system', 'source_type' => 'AutomationRule', 'source_id' => rule.id)
    expect(task.events.find_by!(event_type: 'created').user).to be_nil
  end

  it 'uses the explicit account agent' do
    assignee = create(:user, account: account, role: :agent)
    params.first['assignee_id'] = assignee.id

    expect(service.perform.assigned_to).to eq(assignee)
  end

  it 'leaves the task unassigned when the conversation has no assignee' do
    conversation.update!(assignee: nil)

    expect(service.perform.assigned_to).to be_nil
  end

  %w[minutes hours days].each do |unit|
    it "uses the snooze duration in #{unit} for the due date" do
      params.first['due_in'] = { 'duration' => 2, 'unit' => unit }

      travel_to(Time.zone.local(2026, 10, 23, 12)) do
        expect(service.perform.due_at).to eq(Time.current + 2.public_send(unit))
      end
    end
  end

  it 'deduplicates the same source, conversation and title for 24 hours' do
    task = service.perform

    expect { service.perform }.not_to change(InternalTask, :count)
    key = "internal_task:AutomationRule:#{rule.id}:#{conversation.id}:#{Digest::SHA256.hexdigest(task.title)}"
    expect(Redis::Alfred.ttl(key)).to be_between(86_395, 86_400)
    Redis::Alfred.delete(key)
    expect { service.perform }.to change(InternalTask, :count).by(1)
  end

  it 'does not suppress a different title' do
    service.perform
    params.first['title'] = 'A different task'

    expect { service.perform }.to change(InternalTask, :count).by(1)
  end

  it 'does not suppress a different rule' do
    service.perform
    other_rule = create(:automation_rule, account: account)

    expect do
      described_class.new(conversation: conversation, source: other_rule, params: params).perform
    end.to change(InternalTask, :count).by(1)
  end

  it 'does not suppress a different conversation' do
    service.perform
    other_conversation = create(:conversation, account: account)

    expect do
      described_class.new(conversation: other_conversation, source: rule, params: params).perform
    end.to change(InternalTask, :count).by(1)
  end

  it 'logs stale invalid assignments with the rule id without creating a task' do
    params.first['assignee_id'] = create(:user, account: create(:account)).id
    expect(Rails.logger).to receive(:error).with(a_string_including("rule_id=#{rule.id}", 'create_internal_task', 'agent'))

    expect { service.perform }.not_to change(InternalTask, :count)
  end

  it 'does not create tasks when the account feature is disabled' do
    account.disable_features!('internal_tasks')

    expect { service.perform }.not_to change(InternalTask, :count)
  end

  it 'rechecks the agent role when executing a previously saved action' do
    params.first['assignee_id'] = agent.id
    agent.account_users.find_by!(account: account).update!(role: :administrator)
    expect(Rails.logger).to receive(:error).with(a_string_including("rule_id=#{rule.id}", 'agent of the account'))

    expect { service.perform }.not_to change(InternalTask, :count)
  end

  it 'logs invalid stored due dates without creating a task' do
    params.first['due_in'] = { 'duration' => 366, 'unit' => 'days' }
    expect(Rails.logger).to receive(:error).with(a_string_including("rule_id=#{rule.id}", 'due_in', '365 days'))

    expect { service.perform }.not_to change(InternalTask, :count)
  end

  it 'retains the existing broadcast to the assigned agent and administrators' do
    admin = create(:user, account: account, role: :administrator)
    create(:user, account: account, role: :agent)
    task = service.perform
    event = Events::Base.new(:'internal_task.created', Time.current, internal_task: task)
    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
      'internal_task.created', { internal_task: task.push_event_data, account_id: account.id }
    )

    ActionCableListener.instance.internal_task_created(event)
  end

  it 'retains the visibility scope for the assigned agent and hides the task from unrelated agents' do
    task = service.perform
    outsider = create(:user, account: account, role: :agent)
    assigned_scope = InternalTaskPolicy::Scope.new(
      { user: agent, account: account, account_user: agent.account_users.first }, InternalTask
    )
    other_scope = InternalTaskPolicy::Scope.new(
      { user: outsider, account: account, account_user: outsider.account_users.first }, InternalTask
    )

    expect(assigned_scope.resolve).to include(task)
    expect(other_scope.resolve).not_to include(task)
  end
end
