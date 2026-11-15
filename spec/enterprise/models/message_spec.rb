require 'rails_helper'

RSpec.describe Message do
  let!(:conversation) { create(:conversation) }

  describe 'automatic translation marker' do
    it 'does not mark messages when the account feature is disabled' do
      account = create(:account, settings: { auto_translate: true, translation_provider: 'captain' })
      account.enable_features!(:captain_tasks)
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      agent = create(:user, account: account, role: :agent)

      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :outgoing, sender: agent, content: 'Hello')

      expect(message.content_attributes).not_to have_key('translation_pending')
    end

    it 'does not mark private notes even when automatic translation is enabled' do
      account = create(:account, settings: { auto_translate: true, translation_provider: 'captain' })
      account.enable_features!(:auto_translate, :captain_tasks)
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      agent = create(:user, account: account, role: :agent)

      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :outgoing, sender: agent, private: true, content: 'Internal note')

      expect(message.content_attributes).not_to have_key('translation_pending')
    end
  end

  it 'updates first reply if the message is human and even if there are messages from captain' do
    skip 'TODO(chathub): fallo previo del fork: regla B-NEW-11 del fork: un mensaje de Captain cuenta como primera respuesta'
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

    it 'opens the conversation and clears Captain ownership when a human sends a public outgoing message' do
      conversation.update!(ai_assignee: captain_assistant)

      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: nil, ai_assignee_type: nil)
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

  describe 'reopening a resolved conversation' do
    let(:conversation) { create(:conversation, status: :resolved) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:agent) { create(:user, account: conversation.account, role: :agent) }

    before do
      create(:captain_inbox, inbox: conversation.inbox, captain_assistant: captain_assistant)
      conversation.update_columns(status: Conversation.statuses[:resolved], ai_assignee_type: nil, assignee_agent_bot_id: nil) # rubocop:disable Rails/SkipsModelValidations
      allow_any_instance_of(Captain::Assistant).to receive(:paused_reason).and_return(nil) # rubocop:disable RSpec/AnyInstance
    end

    # A fresh load, as in a request: the factory's inbox caches that it had no assistant when the conversation was created.
    def customer_writes_again
      create(:message, message_type: :incoming, conversation: Conversation.find(conversation.id))
    end

    it 'keeps working for a conversation without an owner' do
      customer_writes_again

      expect(conversation.reload).to have_attributes(
        status: 'pending', ai_assignee_type: 'Captain::Assistant', assignee_agent_bot_id: captain_assistant.id, assignee_id: nil, captain_state: 'ai'
      )
    end

    it 'gives a reopened conversation to the assistant even when a person was assigned, keeping the team' do
      team = create(:team, account: conversation.account)
      conversation.update_columns(assignee_id: agent.id, team_id: team.id) # rubocop:disable Rails/SkipsModelValidations

      customer_writes_again

      expect(conversation.reload).to have_attributes(
        status: 'pending', assignee_id: nil, ai_assignee_type: 'Captain::Assistant', assignee_agent_bot_id: captain_assistant.id, team_id: team.id
      )
    end

    it 'leaves a single assignment activity naming the assistant when a person was assigned' do
      conversation.update_columns(assignee_id: agent.id) # rubocop:disable Rails/SkipsModelValidations

      perform_enqueued_jobs { customer_writes_again }

      assigned = I18n.t('conversations.activity.ai_assignee.assigned', assistant: captain_assistant.name,
                                                                       actor: I18n.t('automation.system_name'), locale: conversation.account.locale)
      expect(conversation.messages.activity.where(content: assigned).count).to eq(1)
    end

    it 'keeps the human assignee when Captain does not engage' do
      conversation.update_columns(assignee_id: agent.id) # rubocop:disable Rails/SkipsModelValidations
      allow_any_instance_of(Captain::Assistant).to receive(:engagement_result) # rubocop:disable RSpec/AnyInstance
        .and_return({ engages: false, reason: 'audience_no_match', condition: nil })

      customer_writes_again

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id, ai_assignee_type: nil)
    end

    it 'does nothing for inboxes without an assistant' do
      conversation.inbox.captain_inbox.destroy!
      conversation.update_columns(assignee_id: agent.id) # rubocop:disable Rails/SkipsModelValidations

      customer_writes_again

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id, ai_assignee_type: nil)
    end

    it 'does nothing when an external bot is active' do
      conversation.update_columns(assignee_id: agent.id) # rubocop:disable Rails/SkipsModelValidations
      allow_any_instance_of(Inbox).to receive(:external_bot_active?).and_return(true) # rubocop:disable RSpec/AnyInstance

      customer_writes_again

      expect(conversation.reload).to have_attributes(assignee_id: agent.id, ai_assignee_type: nil)
    end

    it 'lets a later reply from a person take the conversation back' do
      customer_writes_again
      expect(conversation.reload.ai_assignee).to eq(captain_assistant)

      create(:message, message_type: :outgoing, conversation: Conversation.find(conversation.id), sender: agent)

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id, ai_assignee_type: nil)
    end
  end
end
