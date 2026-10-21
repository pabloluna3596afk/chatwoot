require 'rails_helper'

RSpec.describe Flows::DeferredSendJob do
  let(:conversation) { create(:conversation) }
  let(:account) { conversation.account }
  let(:flow) do
    Flow.create!(account: account, name: 'Variables', graph: {
                   'entry_node_id' => 'save',
                   'nodes' => [{ 'id' => 'save', 'type' => 'set_variable', 'data' => { 'key' => 'x', 'value' => 'saved' } },
                               { 'id' => 'wait', 'type' => 'wait_response' }],
                   'edges' => [{ 'from' => 'save', 'to' => 'wait' }]
                 })
  end
  let(:run) { FlowRun.create!(account: account, conversation: conversation, flow: flow, current_node_id: 'save') }
  let(:execution) { instance_double(Flows::ExecutionService, advance_after_send!: nil) }
  let(:payload) do
    { conversation_id: conversation.id, flow_run_id: run.id, node_id: 'wait',
      content: '{{ flow.x }} / {{ flow.variables.x }}', buttons: [{ title: '{{ flow.x }}', value: '{{ flow.x }}' }] }
  end

  before do
    allow(Flows::ExecutionService).to receive(:new).and_call_original
  end

  it 'reproduces MV-12: saving x makes flow.x available in message content and buttons' do
    Flows::ExecutionService.new(run: run).perform
    expect(run.reload.variables).to eq('x' => 'saved')

    allow(Flows::ExecutionService).to receive(:new).with(run: run).and_return(execution)
    described_class.perform_now(payload)

    message = conversation.messages.outgoing.last
    expect(message.content).to eq('saved / saved')
    expect(message.content_attributes['items']).to eq([{ 'title' => 'saved', 'value' => 'saved' }])
    expect(execution).to have_received(:advance_after_send!).with('wait')
  end

  it 'does not reinterpret Liquid inserted from a run variable' do
    run.update!(variables: { x: '{{ contact.email }}' })

    allow(Flows::ExecutionService).to receive(:new).with(run: run).and_return(execution)
    described_class.perform_now(payload.merge(buttons: []))

    expect(conversation.messages.outgoing.last.content).to eq('{{ contact.email }} / {{ contact.email }}')
  end

  it 'omits a missing run variable with a private reason and advances as skipped' do
    allow(Flows::ExecutionService).to receive(:new).with(run: run).and_return(execution)
    described_class.perform_now(payload)

    expect(conversation.messages.where(private: false)).to be_empty
    expect(conversation.messages.outgoing.last).to have_attributes(private: true)
    expect(conversation.messages.outgoing.last.content).to include('missing')
    expect(execution).to have_received(:advance_after_send!).with('wait', result: { 'skipped' => 'content: missing' })
  end

  it 'does not send after the run has ended' do
    run.update!(state: :completed)

    expect { described_class.perform_now(payload) }.not_to change(Message, :count)
    expect(execution).not_to have_received(:advance_after_send!)
  end
end
