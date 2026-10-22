require 'rails_helper'

RSpec.describe ActionService do
  let(:account) { create(:account, locale: 'es') }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Ventas') }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent) }
  let(:service) { described_class.new(conversation) }

  before do
    account.enable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    allow(Llm::Config).to receive(:api_key_configured?).and_return(true)
    conversation.open!
  end

  it 'replaces a human with the connected Captain without scheduling a response' do
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new)
    service.assign_agent(['captain'])
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: assistant, status: 'pending')
    expect(Notification.where(user: agent, notification_type: 'conversation_assignment')).to be_empty
  end

  it 'leaves a private note naming the assistant and the origin of the assignment' do
    rule = create(:automation_rule, account: account, name: 'Filtro de interesados',
                                    actions: [{ action_name: 'assign_agent', action_params: ['captain'] }])
    AutomationRules::ActionService.new(rule.reload, account, conversation).perform
    note = conversation.messages.where(private: true).order(:id).last
    expect(note.content).to eq('Asignada a Captain Ventas.')
    expect(note.content_attributes).to include('automation_rule_id' => rule.id)
  ensure
    Current.executed_by = nil
  end

  it 'bypasses audience and business hours for an explicit assignment' do
    assistant.update!(config: assistant.config.merge(
      'audience' => { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US'] },
      'response_window' => 'business_hours'
    ))
    inbox.update!(working_hours_enabled: true)
    inbox.working_hours.each { |hours| hours.update!(closed_all_day: true, open_all_day: false) }
    expect(assistant.engages?(conversation.contact, conversation)).to be(false)

    service.assign_agent(['captain'])

    expect(conversation.reload).to have_attributes(ai_assignee: assistant, status: 'pending')
  end

  it 'executes a persisted automation rule with a Captain selector' do
    rule = create(:automation_rule, account: account, actions: [{ action_name: 'assign_agent', action_params: ['captain'] }])
    AutomationRules::ActionService.new(rule.reload, account, conversation).perform
    expect(conversation.reload.ai_assignee).to eq(assistant)
  ensure
    Current.executed_by = nil
  end

  it 'accepts a named assistant and reopens a resolved conversation' do
    conversation.resolved!
    service.assign_agent(["captain:#{assistant.id}"])
    expect(conversation.reload).to have_attributes(ai_assignee: assistant, status: 'pending', assignee_id: nil)
  end

  it 'does not write or produce notes when already pending with that Captain' do
    Conversations::AssignmentService.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    expect { service.assign_agent(['captain']) }.not_to(change { conversation.reload.updated_at })
    expect { service.assign_agent(['captain']) }.not_to change(Message, :count)
  end

  {
    disabled: 'Captain no está habilitado en esta cuenta.',
    disconnected: 'Esta Bandeja no tiene Captain conectado.',
    different: 'El asistente elegido no está conectado a esta Bandeja.',
    external_bot: 'Esta Bandeja tiene un bot externo activo.',
    missing_key: 'Captain está en pausa porque falta la clave de IA.',
    quota_exhausted: 'Captain está en pausa porque no quedan respuestas disponibles.'
  }.each do |reason, text|
    it "preserves conversation ownership and status when #{reason}" do
      account.disable_features!('captain_integration') if reason == :disabled
      inbox.captain_inbox.destroy! if reason == :disconnected
      create(:agent_bot_inbox, inbox: inbox, status: :active) if reason == :external_bot
      allow(Llm::Config).to receive(:api_key_configured?).and_return(false) if reason == :missing_key
      account.update!(limits: { 'captain_responses' => 0 }) if reason == :quota_exhausted
      selector = reason == :different ? "captain:#{assistant.id + 1}" : 'captain'
      original = conversation.attributes.slice('status', 'assignee_id', 'assignee_agent_bot_id', 'ai_assignee_type', 'additional_attributes')

      service.assign_agent([selector])

      expect(conversation.reload.attributes.slice(*original.keys)).to eq(original)
      expect(conversation.messages.last).to have_attributes(private: true, content: "No se asignó a Captain: #{text}")
    end
  end

  it 'keeps numeric human assignments working' do
    create(:inbox_member, inbox: inbox, user: agent)
    service.assign_agent([agent.id])
    expect(conversation.reload.assignee).to eq(agent)
  end

  it 'persists and executes Captain in a macro' do
    macro = create(:macro, account: account, actions: [{ action_name: 'assign_agent', action_params: ["captain:#{assistant.id}"] }])
    Macros::ExecutionService.new(macro.reload, conversation, agent).perform
    expect(conversation.reload.ai_assignee).to eq(assistant)
  end

  it 'records a skipped flow step with its reason' do
    flow = Flow.create!(account: account, name: 'Captain')
    run = FlowRun.create!(account: account, flow: flow, conversation: conversation)
    inbox.captain_inbox.destroy!
    Flows::ActionService.new(conversation: conversation, flow_run: run).execute(action_name: 'assign_agent', action_params: ['captain'])
    expect(run.flow_events.last).to have_attributes(event_type: 'captain_assignment_skipped', data: include('reason' => 'disconnected'))
  end

  it 'assigns Captain on flow exit even when the configured status is resolved' do
    flow = Flow.create!(account: account, name: 'Captain', exit_policy: {
                          on_complete: { status: 'resolved', assignee_mode: 'captain', assistant_id: assistant.id }
                        })
    run = FlowRun.create!(account: account, flow: flow, conversation: conversation)
    Flows::ExitPolicyService.new(run: run, event: 'on_complete').perform
    expect(conversation.reload).to have_attributes(ai_assignee: assistant, status: 'pending', assignee_id: nil)
  end

  it 'preserves status and ownership on a blocked Captain flow exit and records the reason' do
    flow = Flow.create!(account: account, name: 'Captain', exit_policy: {
                          on_complete: { status: 'resolved', assignee_mode: 'captain' }
                        })
    run = FlowRun.create!(account: account, flow: flow, conversation: conversation)
    inbox.captain_inbox.destroy!
    Flows::ExitPolicyService.new(run: run, event: 'on_complete').perform
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    expect(run.flow_events.where(event_type: 'captain_assignment_skipped').last.data).to include('reason' => 'disconnected')
  end

  %w[captain captain:123].each do |selector|
    it "round trips #{selector} through automation validation and the single value linter" do
      rule = create(:automation_rule, account: account, actions: [{ action_name: 'assign_agent', action_params: [selector] }])
      expect(rule.reload.actions.first['action_params']).to eq([selector])
      expect(rule).to be_valid
      human_rule = create(:automation_rule, account: account, actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
      findings = AutomationRules::CrossRuleLinter.new(rules: [rule, human_rule]).perform
      expect(findings.map(&:code)).to include('conflicting_action_values')
    end
  end

  it 'does not schedule the triggering message but schedules the next customer message' do
    message = create(:message, :incoming, conversation: conversation, account: account, inbox: inbox)
    service.assign_agent(['captain'])
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new).with(message: message)
    MessageTemplates::HookExecutionService.new(message: message).perform

    scheduler = instance_double(Captain::Conversation::ResponseSchedulerService, perform: nil)
    expect(Captain::Conversation::ResponseSchedulerService).to receive(:new).and_return(scheduler)
    create(:message, :incoming, conversation: conversation, account: account, inbox: inbox)
  end

  it 'discards an already queued response until another customer message arrives' do
    conversation.pending!
    create(:message, :incoming, conversation: conversation, account: account, inbox: inbox)
    service.assign_agent(['captain'])
    expect(Captain::Llm::AssistantChatService).not_to receive(:new)
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation.reload, assistant)
  end
end
