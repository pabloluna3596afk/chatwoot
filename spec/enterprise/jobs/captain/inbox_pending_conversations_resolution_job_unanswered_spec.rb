require 'rails_helper'

RSpec.describe Captain::InboxPendingConversationsResolutionJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:action) { 'close' }
  let(:mode) { 'evaluated' }
  let(:send_goodbye) { true }
  let(:window_open) { true }
  let(:followup) { { 'inactivity_enabled' => false } }
  let(:assistant) do
    create(:captain_assistant, account: account, config: {
             'unanswered_action' => action, 'auto_resolve_mode' => mode, 'followup' => followup,
             'send_inactivity_resolution_message' => send_goodbye, 'resolution_message' => 'Goodbye'
           })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }
  let(:job) { described_class.new }
  let(:evaluation) { instance_double(Captain::ConversationCompletionService, perform: { complete: false, reason: 'Needs reply' }) }

  before do
    account.enable_features!('captain_integration_v2')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    create(:message, account: account, conversation: conversation, sender: assistant, message_type: :outgoing, created_at: 2.hours.ago)
    conversation.update!(last_activity_at: 2.hours.ago)
    allow(Captain::ConversationCompletionService).to receive(:new).and_return(evaluation)
    allow(job).to receive(:evaluate_conversation_completion?).and_return(mode == 'evaluated')
  end

  %w[evaluated legacy].each do |resolution_mode|
    context "with #{resolution_mode} resolution" do
      let(:mode) { resolution_mode }

      it 'closes without evaluating, even outside a pilot account' do
        expect(Captain::Pilot.enabled?(account)).to be(false)
        expect(evaluation).not_to receive(:perform)
        job.perform(inbox)
        expect(conversation.reload).to be_resolved
        expect(conversation.messages.where(private: true).last.content).to eq(
          I18n.t('captain.notes.closed_unanswered', assistant: assistant.name, locale: account.locale)
        )
        expect(conversation.additional_attributes['captain_followup']).to include('assistant_id' => assistant.id)
      end

      context 'with the admin closing-message setting' do
        before do
          allow(job).to receive(:resolvable_pending_conversations).with(inbox).and_return([conversation])
          allow(conversation).to receive(:can_reply?).and_return(window_open)
        end

        it 'sends the goodbye when the assistant has it enabled and the window is open' do
          expect(evaluation).not_to receive(:perform)
          expect { job.perform(inbox) }.to change { conversation.messages.where(private: false, message_type: :outgoing).count }.by(1)
          expect(conversation.messages.where(private: false, message_type: :outgoing).order(:id).last.content).to eq('Goodbye')
          expect(conversation.reload).to be_resolved
        end

        context 'when the admin disables the goodbye' do
          let(:send_goodbye) { false }

          it 'sends nothing when it is disabled' do
            expect(evaluation).not_to receive(:perform)
            expect { job.perform(inbox) }.not_to(change { conversation.messages.where(private: false, message_type: :outgoing).count })
            expect(conversation.reload).to be_resolved
          end
        end

        context 'when the reply window is closed' do
          let(:window_open) { false }

          it 'sends nothing when the window is closed' do
            expect(evaluation).not_to receive(:perform)
            expect { job.perform(inbox) }.not_to(change { conversation.messages.where(private: false, message_type: :outgoing).count })
            expect(conversation.reload).to be_resolved
          end
        end
      end

      context 'with follow-up enabled' do
        let(:followup) { { 'inactivity_enabled' => true, 'max_nudges' => 1 } }

        it 'leaves it to the nudger without evaluating or writing a note' do
          expect(evaluation).not_to receive(:perform)
          expect { job.perform(inbox) }.not_to(change { conversation.messages.count })
          expect(conversation.reload).to be_pending
        end
      end

      context 'with zero nudges' do
        let(:followup) { { 'inactivity_enabled' => true, 'max_nudges' => 0 } }

        it 'closes instead of waiting for the dispatcher' do
          job.perform(inbox)
          expect(conversation.reload).to be_resolved
        end
      end

      context 'with leave_open' do
        let(:action) { 'leave_open' }

        it 'does nothing' do
          expect(evaluation).not_to receive(:perform)
          expect { job.perform(inbox) }.not_to(change { conversation.messages.count })
          expect(conversation.reload).to be_pending
        end
      end
    end
  end

  context 'with handoff' do
    let(:action) { 'handoff' }

    it 'keeps the previous evaluation and handoff path' do
      expect(evaluation).to receive(:perform).and_return(complete: false, reason: 'Needs reply')
      job.perform(inbox)
      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes).not_to have_key('captain_followup')
    end
  end

  %w[close handoff leave_open].each do |unanswered_action|
    context "when the customer spoke last and action is #{unanswered_action}" do
      let(:action) { unanswered_action }

      it 'still evaluates and hands off' do
        create(:message, account: account, conversation: conversation, sender: conversation.contact,
                         message_type: :incoming, created_at: 90.minutes.ago)
        conversation.update!(last_activity_at: 90.minutes.ago)
        expect(evaluation).to receive(:perform).and_return(complete: false, reason: 'Needs answer')
        job.perform(inbox)
        expect(conversation.reload).to be_open
      end
    end
  end

  it 'does not act when auto resolution is disabled' do
    assistant.update!(auto_resolve_mode: 'disabled')
    inbox.reload
    expect { job.perform(inbox) }.not_to(change { conversation.messages.count })
    expect(conversation.reload).to be_pending
  end

  it 'does not close after a human takes ownership between selection and locking' do
    human = create(:user, account: account)
    allow(job).to receive(:resolvable_pending_conversations).with(inbox).and_return([conversation])
    allow(conversation).to receive(:with_lock).and_wrap_original do |original, &block|
      Conversation.find(conversation.id).update!(assignee: human)
      original.call(&block)
    end
    expect { job.perform(inbox) }.not_to(change { conversation.messages.count })
    expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: human.id, ai_assignee: nil)
  end

  it 'does not close after another assistant takes ownership between selection and locking' do
    other = create(:captain_assistant, account: account)
    allow(job).to receive(:resolvable_pending_conversations).with(inbox).and_return([conversation])
    allow(conversation).to receive(:with_lock).and_wrap_original do |original, &block|
      Conversation.find(conversation.id).update!(ai_assignee: other)
      original.call(&block)
    end
    expect { job.perform(inbox) }.not_to(change { conversation.messages.count })
    expect(conversation.reload).to have_attributes(status: 'pending', ai_assignee: other)
  end

  it 'does not close if a customer replies between selection and locking' do
    allow(job).to receive(:resolvable_pending_conversations).with(inbox).and_return([conversation])
    allow(conversation).to receive(:with_lock).and_wrap_original do |original, &block|
      create(:message, account: account, conversation: Conversation.find(conversation.id), sender: conversation.contact, message_type: :incoming)
      original.call(&block)
    end
    job.perform(inbox)
    expect(conversation.reload).to be_pending
    expect(conversation.messages.where(private: true)).to be_empty
  end
end
