require 'rails_helper'

RSpec.describe Captain::Conversation::CompletionSignal do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) do
    create(:captain_assistant, account: account, config: { auto_resolve_mode: 'evaluated', completion_signal_enabled: true })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }
  let(:incoming) { create(:message, conversation: conversation, message_type: :incoming, sender: conversation.contact) }
  let(:reply) { create(:message, conversation: conversation, message_type: :outgoing, sender: assistant, content: 'Goodbye, glad I could help.') }
  let(:signal) { described_class.new(conversation, assistant) }
  let(:response) { { 'probable_complete' => true, 'expects_customer_reply' => false } }
  let(:evaluation) { instance_double(Captain::ConversationCompletionService, perform: { complete: true, reason: 'Done' }) }

  before do
    account.enable_features!('captain_integration_v2', 'captain_tasks')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    incoming
    reply
    allow(Captain::ConversationCompletionService).to receive(:new).and_return(evaluation)
    signal.record(message: reply, response: response, incoming_id: incoming.id)
  end

  after { Current.reset }

  it 'waits for the server grace, then closes without a goodbye or re-engagement' do
    signal.review
    expect(evaluation).not_to have_received(:perform)
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]).to include('reply_id' => reply.id, 'incoming_id' => incoming.id)

    travel 6.minutes do
      expect { Captain::ReviewCompletionSignalsJob.perform_now }.not_to(change { conversation.messages.count })
    end
    expect(conversation.reload).to be_resolved
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('confirmed')
    expect(conversation.additional_attributes).not_to have_key(Captain::Followup::Reengager::STATE_KEY)
  end

  it 'does not review the same turn twice or recreate its candidate' do
    expect(evaluation).to receive(:perform).once
    travel 6.minutes do
      signal.review
      signal.review
      signal.record(message: reply, response: response, incoming_id: incoming.id)
      Captain::ReviewCompletionSignalsJob.perform_now
    end
  end

  it 'returns a rejected candidate to the normal flow without a handoff' do
    allow(evaluation).to receive(:perform).and_return(complete: false, expects_customer_reply: true, reason: 'Needs details')
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.ai_assignee).to eq(assistant)
    expect(conversation.additional_attributes[described_class::KEY]).to include('status' => 'rejected', 'expects_customer_reply' => true)
    expect(Captain::Conversation::Turn.awaiting_customer?(conversation, assistant)).to be(true)
  end

  it 'does not resume reminders after rejection unless a customer reply is really expected' do
    allow(evaluation).to receive(:perform).and_return(complete: false, reason: 'Needs an agent action')
    travel(6.minutes) { signal.review }
    expect(Captain::Conversation::Turn.awaiting_customer?(conversation.reload, assistant)).to be(false)
  end

  it 'retires an evaluation error without declaring success' do
    allow(evaluation).to receive(:perform).and_return(complete: false, error: :failed)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('failed')
    expect(evaluation).not_to receive(:perform)
    travel(7.minutes) { signal.review }
  end

  it 'retires a raised model error without closing or handing off' do
    allow(evaluation).to receive(:perform).and_raise(StandardError, 'model down')
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('failed')
  end

  it 'cancels a candidate on an incoming message' do
    create(:message, conversation: conversation, message_type: :incoming, sender: conversation.contact)
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'discards a positive result if a message arrives during evaluation' do
    allow(evaluation).to receive(:perform) do
      create(:message, conversation: Conversation.find(conversation.id), message_type: :incoming, sender: conversation.contact)
      { complete: true, reason: 'Done' }
    end
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'cancels on a public human response' do
    create(:message, conversation: conversation, message_type: :outgoing, sender: create(:user, account: account))
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_open
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'cancels on human assignment even if the assignment is later removed' do
    conversation.update!(assignee: create(:user, account: account))
    conversation.update!(assignee: nil, ai_assignee: assistant)
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'discards a positive result when a human takes ownership during evaluation' do
    human = create(:user, account: account)
    allow(evaluation).to receive(:perform) do
      Conversation.find(conversation.id).update!(assignee: human)
      { complete: true, reason: 'Done' }
    end
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: human.id)
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'retires a candidate whose owner disappeared between job selection and review' do
    travel(6.minutes) { described_class.new(conversation, nil).review }
    expect(evaluation).not_to have_received(:perform)
    expect(conversation.reload.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'cancels on handoff' do
    conversation.bot_handoff!
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_open
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'cancels when the assistant changes' do
    conversation.update!(ai_assignee: create(:captain_assistant, account: account))
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'closes silently with an expired reply window, even with a goodbye configured' do
    assistant.update!(send_inactivity_resolution_message: true)
    allow(conversation).to receive(:can_reply?).and_return(false)
    travel(6.minutes) { expect { signal.review }.not_to(change { conversation.messages.count }) }
    expect(conversation.reload).to be_resolved
  end

  it 'does not nudge a farewell that expects no customer reply' do
    travel 40.minutes do
      expect(Captain::Conversation::Turn.awaiting_customer?(conversation, assistant)).to be(false)
      expect { Captain::Followup::Nudger.new(conversation, assistant).perform }.not_to(change { conversation.messages.count })
    end
  end

  it 'ignores an unstructured reasoning string and does not claim a new candidate' do
    conversation.update!(additional_attributes: {})
    signal.record(message: reply, response: { 'reasoning' => 'probable_complete: true, expects_customer_reply: false' }, incoming_id: incoming.id)
    expect(conversation.reload.additional_attributes).not_to have_key(described_class::KEY)
  end

  it 'does not overwrite a newer turn with an older candidate' do
    newer = create(:message, conversation: conversation, message_type: :incoming, sender: conversation.contact)
    signal.record(message: reply, response: response, incoming_id: incoming.id)
    expect(conversation.reload.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
    expect(newer.id).to be > incoming.id
  end

  it 'does not schedule a candidate with a required customer reply' do
    conversation.update!(additional_attributes: {})
    signal.record(message: reply, response: response.merge('expects_customer_reply' => true), incoming_id: incoming.id)
    expect(conversation.reload.additional_attributes[described_class::KEY]['status']).to eq('observed')
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
  end

  it 'does not let the long reviewer evaluate or close the same candidate' do
    allow(evaluation).to receive(:perform) do
      Captain::InboxPendingConversationsResolutionJob.perform_now(inbox)
      { complete: true, reason: 'Done' }
    end
    travel(40.minutes) { signal.review }
    expect(evaluation).to have_received(:perform).once
    expect(conversation.reload).to be_resolved
  end

  it 'retires a crashed evaluation lease without another model call' do
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(
      described_class::KEY => conversation.additional_attributes[described_class::KEY].merge(
        'status' => 'evaluating', 'evaluating_at' => 10.minutes.ago.utc.iso8601
      )
    ))
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { Captain::ReviewCompletionSignalsJob.perform_now }
    expect(conversation.reload.additional_attributes[described_class::KEY]).to include('status' => 'failed', 'error' => 'evaluation_interrupted')
    expect(conversation).to be_pending
  end

  it 'discards the result when detection is disabled while evaluating' do
    allow(evaluation).to receive(:perform) do
      assistant.update!(config: assistant.config.merge('completion_signal_enabled' => false))
      { complete: true, reason: 'Done' }
    end
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end

  it 'distinguishes customer confirmation in the resolution event' do
    allow(evaluation).to receive(:perform).and_return(complete: true, reason: 'Customer confirmed', customer_confirmed: true)
    expect(Captain::ConversationEvents).to receive(:resolved).with(
      conversation: conversation, assistant: assistant, source: 'inference', at: kind_of(Time), reason: 'customer_confirmation'
    )
    travel(6.minutes) { signal.review }
  end

  it 'cancels on a changed inbox assistant even when changed back before review' do
    link = inbox.captain_inbox
    link.update!(captain_assistant: create(:captain_assistant, account: account))
    link.update!(captain_assistant: assistant)
    expect(evaluation).not_to receive(:perform)
    travel(6.minutes) { signal.review }
    expect(conversation.reload).to be_pending
    expect(conversation.additional_attributes[described_class::KEY]['status']).to eq('cancelled')
  end
end
