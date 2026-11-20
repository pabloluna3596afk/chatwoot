require 'rails_helper'

RSpec.describe Captain::Conversation::LoopGuard do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { auto_resolve_mode: 'evaluated', completion_signal_enabled: true }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant).reload }
  let(:guard) { described_class.new(conversation, assistant) }
  let(:response) { { 'probable_complete' => true, 'expects_customer_reply' => false } }
  let(:evaluation) { instance_double(Captain::ConversationCompletionService, perform: { complete: true, reason: 'Done' }) }
  let(:incoming) { conversation.messages.incoming.order(:id).last }

  before do
    account.enable_features!('captain_integration_v2')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    allow(Captain::ConversationCompletionService).to receive(:new).and_return(evaluation)
  end

  after { Current.reset }

  it 'stops a simulated fourteen-turn exchange every ten seconds after four closing replies' do
    start = Time.current
    14.times do |index|
      travel_to(start + (index * 10.seconds)) do
        next unless conversation.reload.pending?

        message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Thank you')
        next if guard.perform(message.id)

        reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant, content: 'Welcome')
        guard.record(reply, response)
      end
    end
    expect(conversation.reload).to be_resolved
    expect(conversation.messages.outgoing.where(private: false).count).to eq(4)
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(evaluation).to have_received(:perform).once
  end

  context 'with four recent closing turns' do
    before do
      start = 40.seconds.ago
      4.times do |index|
        travel_to(start + (index * 10.seconds)) do
          message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: "Thanks #{index}")
          reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant, content: 'Welcome')
          guard.record(reply, response)
          Captain::Conversation::CompletionSignal.new(conversation, assistant).record(message: reply, response: response,
                                                                                      incoming_id: message.id)
        end
      end
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Thanks again')
    end

    it 'suppresses fourteen repeated response jobs at the threshold without reserving credits or generating a reply' do
      expect(assistant).to receive(:reply_limit_reached?).with(conversation).and_call_original
      job = Captain::Conversation::ResponseBuilderJob.new
      expect(job).not_to receive(:reserve_reply_usage!)
      expect(Captain::Llm::AssistantChatService).not_to receive(:new)
      expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)
      14.times do
        travel 10.seconds do
          job.perform(conversation, assistant, incoming.id)
        end
      end
      expect(evaluation).to have_received(:perform).once
      expect(conversation.messages.outgoing.where(private: false).count).to eq(4)
      expect(conversation.captain_decisions.where(kind: 'loop_guard').pluck(:outcome)).to contain_exactly('pending', 'confirmed')
    end

    it 'preserves the existing closing deadline on a repetitive incoming' do
      expect(conversation.reload.additional_attributes[Captain::Conversation::CompletionSignal::KEY]['status']).to eq('pending')
    end

    [false, :failed, :raised].each do |result|
      it "hands off once without a public message when review returns #{result}" do
        if result == :raised
          allow(evaluation).to receive(:perform).and_raise(StandardError, 'unavailable')
          allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
        else
          allow(evaluation).to receive(:perform).and_return(result == false ? { complete: false } : { error: :failed })
        end
        2.times { guard.perform(incoming.id) }
        expect(conversation.reload).to be_open
        expect(conversation.ai_assignee).to be_nil
        expect(conversation.messages.outgoing.where(private: false).count).to eq(4)
        expect(conversation.messages.where(private: true).count).to eq(1)
        expect(conversation.captain_decisions.where(kind: 'loop_guard', outcome: 'confirmed')).to be_empty
      end
    end

    it 'does not close when a new customer message arrives during review' do
      allow(evaluation).to receive(:perform) do
        create(:message, account: account, conversation: Conversation.find(conversation.id), message_type: :incoming, content: 'A new question')
        { complete: true }
      end
      guard.perform(incoming.id)
      expect(conversation.reload).to be_pending
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'does not close when a human takes ownership during review' do
      human = create(:user, account: account)
      allow(evaluation).to receive(:perform) do
        Conversation.find(conversation.id).update!(assignee: human)
        { complete: true }
      end
      guard.perform(incoming.id)
      expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: human.id)
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'cancels after human assignment even when removed again' do
      conversation.update!(assignee: create(:user, account: account))
      conversation.update!(assignee: nil, ai_assignee: assistant)
      expect(guard.perform(incoming.id)).to be(false)
      expect(evaluation).not_to have_received(:perform)
    end

    it 'cancels after a public human reply' do
      create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: create(:user, account: account))
      expect(guard.perform(incoming.id)).to be(false)
      expect(evaluation).not_to have_received(:perform)
    end

    it 'cancels after changing the inbox assistant and back' do
      link = inbox.captain_inbox
      link.update!(captain_assistant: create(:captain_assistant, account: account))
      link.update!(captain_assistant: assistant)
      expect(guard.perform(incoming.id)).to be(false)
      expect(evaluation).not_to have_received(:perform)
    end

    it 'discards a positive review when the assistant changes during evaluation' do
      allow(evaluation).to receive(:perform) do
        conversation.inbox.captain_inbox.update!(captain_assistant: create(:captain_assistant, account: account))
        { complete: true }
      end
      guard.perform(incoming.id)
      expect(conversation.reload).to be_pending
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'suppresses a duplicate worker while the reviewer is running' do
      allow(evaluation).to receive(:perform) do
        expect(described_class.new(Conversation.find(conversation.id), assistant).perform(incoming.id)).to be(true)
        { complete: true }
      end
      guard.perform(incoming.id)
      expect(evaluation).to have_received(:perform).once
      expect(conversation.reload).to be_resolved
      expect(conversation.messages.where(private: true).count).to eq(1)
    end

    it 'hands off an interrupted reviewer without a second model call' do
      attributes = conversation.additional_attributes.deep_dup
      attributes[described_class::KEY].merge!('status' => 'evaluating', 'evaluating_at' => 6.minutes.ago.to_f, 'incoming_id' => incoming.id)
      conversation.update!(additional_attributes: attributes)
      guard.perform(incoming.id)
      expect(evaluation).not_to have_received(:perform)
      expect(conversation.reload).to be_open
      expect(conversation.captain_decisions.where(kind: 'loop_guard', outcome: 'failed')).to exist
    end

    it 'closes silently outside the reply window' do
      allow(conversation).to receive(:can_reply?).and_return(false)
      guard.perform(incoming.id)
      expect(conversation.reload).to be_resolved
      expect(conversation.messages.outgoing.where(private: false).count).to eq(4)
    end

    %w[en es].each do |locale|
      it "records an account-language private note and zero-credit decision in #{locale}" do
        account.update!(locale: locale)
        guard.perform(incoming.id)
        note = conversation.messages.where(private: true).sole
        decision = conversation.captain_decisions.find_by!(kind: 'loop_guard', outcome: 'confirmed')
        expect(note.content).to eq(I18n.t('captain.decisions.loop_guard', locale: locale))
        expect(decision).to have_attributes(reason_locale: locale, reason_text: note.content, technical_details: { 'credits_consumed' => 0 })
      end
    end

    it 'uses the existing reply cap before attempting a loop review' do
      assistant.update!(config: assistant.config.merge('max_replies_per_conversation' => 4))
      job = Captain::Conversation::ResponseBuilderJob.new
      expect(job).to receive(:process_reply_limit)
      job.perform(conversation, assistant, incoming.id)
      expect(evaluation).not_to have_received(:perform)
    end

    it 'does not use stale closing turns beyond the configured window' do
      travel 4.minutes do
        expect(guard.perform(incoming.id)).to be(false)
      end
      expect(evaluation).not_to have_received(:perform)
    end

    it 'protects assistants with completion signals disabled' do
      assistant.update!(config: assistant.config.merge('completion_signal_enabled' => false))
      guard.perform(incoming.id)
      expect(conversation.reload).to be_resolved
      expect(evaluation).to have_received(:perform).once
    end

    it 'hands off when automatic closure is explicitly disabled' do
      assistant.update!(config: assistant.config.merge('auto_resolve_mode' => 'disabled'))
      guard.perform(incoming.id)
      expect(conversation.reload).to be_open
      expect(conversation.captain_decisions.where(kind: 'loop_guard', outcome: 'confirmed')).to be_empty
    end

    it 'does not record success when the final resolution check declines the transition' do
      allow(Captain::Conversation::ResolutionTransition).to receive(:perform).and_return(nil)
      guard.perform(incoming.id)
      expect(conversation.reload).to be_open
      expect(conversation.captain_decisions.where(kind: 'loop_guard', outcome: 'confirmed')).to be_empty
      expect(conversation.captain_decisions.where(kind: 'loop_guard', outcome: 'rejected')).to exist
    end
  end

  it 'allows ten real questions at one minute intervals expecting a customer reply' do
    10.times do |index|
      travel_to(Time.current + index.minutes) do
        message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: "Question #{index}?")
        expect(guard.perform(message.id)).to be(false)
        reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant, content: 'Which option?')
        guard.record(reply, 'probable_complete' => false, 'expects_customer_reply' => true)
      end
    end
    expect(evaluation).not_to have_received(:perform)
    expect(conversation.reload).to be_pending
  end

  it 'detects fast alternating legacy turns without completion flags' do
    4.times do
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant)
      guard.record(reply, {})
    end
    create(:message, account: account, conversation: conversation, message_type: :incoming)
    expect(guard.detected?).to be(true)
  end

  it 'allows fast substantive exchanges when the responses expect customer input' do
    4.times do
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant)
      guard.record(reply, 'probable_complete' => false, 'expects_customer_reply' => true)
    end
    message = create(:message, account: account, conversation: conversation, message_type: :incoming)
    expect(guard.perform(message.id)).to be(false)
    expect(evaluation).not_to have_received(:perform)
  end
end
