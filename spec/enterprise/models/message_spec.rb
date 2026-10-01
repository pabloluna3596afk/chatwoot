require 'rails_helper'

RSpec.describe Message do
  let!(:conversation) { create(:conversation) }

  it 'updates first reply if the message is human and even if there are messages from captain' do
    captain_assistant = create(:captain_assistant, account: conversation.account)
    expect(conversation.first_reply_created_at).to be_nil

    ## There is a difference on how the time is stored in the database and how it is retrieved
    # This is because of the precision of the time stored in the database
    # In the test, we will check whether the time is within the range
    expect(conversation.waiting_since).to be_within(0.000001.seconds).of(conversation.created_at)

    create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)

    # Captain::Assistant responses clear waiting_since (like AgentBot)
    expect(conversation.first_reply_created_at).to be_nil
    expect(conversation.waiting_since).to be_nil

    create(:message, message_type: :outgoing, conversation: conversation)

    expect(conversation.first_reply_created_at).not_to be_nil
    expect(conversation.waiting_since).to be_nil
  end

  describe '#mark_pending_conversation_as_open_for_human_response' do
    let(:conversation) { create(:conversation, status: :pending) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:auto_open_activity_content) { I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale) }

    before do
      create(:captain_inbox, inbox: conversation.inbox, captain_assistant: captain_assistant)
    end

    it 'marks the conversation open when a human sends a public outgoing message' do
      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload.open?).to be true
    end

    it 'creates an activity message when a human sends a public outgoing message' do
      expect do
        create(:message, message_type: :outgoing, conversation: conversation)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'creates an activity message for external echo replies' do
      message = build(
        :message,
        message_type: :outgoing,
        conversation: conversation,
        content_attributes: { external_echo: true }
      )
      message.sender = nil

      expect do
        message.save!
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'does not mark the conversation open for private outgoing messages' do
      create(:message, message_type: :outgoing, conversation: conversation, private: true)

      expect(conversation.reload.pending?).to be true
    end

    it 'does not mark the conversation open for bot outgoing messages' do
      agent_bot = create(:agent_bot, account: conversation.account)
      create(:message, message_type: :outgoing, conversation: conversation, sender: agent_bot)

      expect(conversation.reload.pending?).to be true
    end

    it 'assigns the agent who replies to a conversation Captain was attending' do
      agent = create(:user, account: conversation.account)

      create(:message, message_type: :outgoing, conversation: conversation, sender: agent)

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
      expect(conversation.captain_state).to be_nil
    end

    it 'does not assign anyone when the reply has no user sender' do
      message = build(:message, message_type: :outgoing, conversation: conversation, content_attributes: { external_echo: true })
      message.sender = nil
      message.save!

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: nil)
    end

    it 'keeps the assignee of a conversation that already has a human' do
      owner = create(:user, account: conversation.account)
      other_agent = create(:user, account: conversation.account)
      conversation.update!(assignee: owner)

      create(:message, message_type: :outgoing, conversation: conversation, sender: other_agent)

      expect(conversation.reload.assignee_id).to eq(owner.id)
    end

    context 'when the conversation was escalated by Captain' do
      let(:agent) { create(:user, account: conversation.account) }

      before do
        conversation.update!(status: :open)
        conversation.update!(captain_handed_off_at: Time.current)
      end

      it 'assigns the agent who replies and clears the escalation mark' do
        expect(conversation.reload.captain_state).to eq('escalated')

        create(:message, message_type: :outgoing, conversation: conversation, sender: agent)

        expect(conversation.reload).to have_attributes(assignee_id: agent.id, captain_handed_off_at: nil)
        expect(conversation.captain_state).to be_nil
      end

      it 'does not create the auto-open activity message because the conversation was already open' do
        expect do
          create(:message, message_type: :outgoing, conversation: conversation, sender: agent)
        end.not_to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: auto_open_activity_content))
      end

      it 'does not take the conversation for private notes' do
        create(:message, message_type: :outgoing, conversation: conversation, sender: agent, private: true)

        expect(conversation.reload).to have_attributes(assignee_id: nil, captain_state: 'escalated')
      end
    end
  end
end
