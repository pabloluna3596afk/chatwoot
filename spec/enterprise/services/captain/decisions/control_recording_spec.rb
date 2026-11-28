require 'rails_helper'

RSpec.describe Captain::Decisions::ControlRecording do
  let(:account) { create(:account, locale: 'es') }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }

  before do
    account.enable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end
  after { Current.reset }

  it 'records human takeover on the one existing activity with the actual author' do
    conversation
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) do
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent, message_type: :outgoing)
    end
    decision = conversation.captain_decisions.find_by!(kind: 'human_control')
    expect(conversation.messages.activity.count).to eq(1)
    expect(decision.anchor_message).to eq(conversation.messages.activity.sole)
    expect(decision.anchor_message.content_attributes.dig('activity', 'source')).to eq('type' => 'user', 'name' => agent.name)
    expect(decision.reason_text).to include('Una persona tomó el control')
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    expect(conversation.captain_decisions.where(kind: 'human_control').count).to eq(1)
  end

  it 'records an explicit assignment on the existing assignment activity' do
    conversation
    Current.user = agent
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { conversation.update!(assignee: agent, ai_assignee: nil, status: :open) }
    decision = conversation.captain_decisions.find_by!(kind: 'human_control')
    expect(decision.anchor_message).to be_present
    expect(decision.anchor_message.content_attributes.dig('activity', 'captain_event')).to eq('human_control')
    expect { conversation.save! }.not_to(change { conversation.captain_decisions.count })
  end

  it 'records a customer reopening to pending even though the next owner is Captain' do
    conversation.resolved!
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, message_type: :incoming)
    expect(conversation.reload).to be_pending
    expect(conversation.captain_decisions.find_by!(kind: 'reopen')).to have_attributes(anchor_message: incoming, trigger: 'customer_message')
  end

  it 'records a human reply taking an already open escalation on the reply itself' do
    conversation.bot_handoff!
    reply = create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent, message_type: :outgoing)
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    expect(conversation.captain_decisions.find_by!(kind: 'human_control')).to have_attributes(anchor_message: reply)
  end

  it 'records a direct assignment of an open escalation on its assignment activity' do
    conversation.bot_handoff!
    Current.user = agent
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { conversation.update!(assignee: agent) }
    decision = conversation.captain_decisions.find_by!(kind: 'human_control')
    expect(decision.anchor_message).to be_activity
    expect(conversation.reload.captain_handed_off_at).to be_nil
  end

  it 'preserves automation as the actor instead of claiming that a person replied' do
    conversation
    rule = create(:automation_rule, account: account)
    Current.executed_by = rule
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) do
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: nil, message_type: :outgoing)
    end
    decision = conversation.captain_decisions.find_by!(kind: 'disengage')
    expect(decision.anchor_message.content_attributes.dig('activity', 'source')).to eq('type' => 'automation_rule', 'name' => rule.name)
    expect(conversation.captain_decisions.where(kind: 'human_control')).to be_empty
    expect(Current.executed_by).to eq(rule)
  end

  it 'records external echo without inventing a human author' do
    echo = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                           content_attributes: { external_echo: true })
    echo.sender = nil
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { echo.save! }
    decision = conversation.captain_decisions.find_by!(kind: 'disengage')
    expect(decision.anchor_message.content_attributes.dig('activity', 'source')).to eq('type' => 'external_echo')
    expect(conversation.captain_decisions.where(kind: 'human_control')).to be_empty
  end

  it 'records engagement exclusion on its existing activity without another note' do
    conversation.record_captain_skip(assistant, engages: false, reason: 'audience_denied', condition: { attribute_key: 'phone_number' })
    conversation.open!
    decision = conversation.captain_decisions.find_by!(kind: 'disengage', trigger: 'engagement')
    expect(decision.anchor_message).to be_activity
    expect(decision.anchor_message.additional_attributes.dig('captain_skip_reason', 'reason')).to eq('audience_denied')
    expect(conversation.messages.activity.count).to eq(1)
  end

  it 'keeps human takeover when recording fails' do
    conversation
    allow(Captain::Decision).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent, message_type: :outgoing)
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: agent.id)
    expect(conversation.captain_decisions).to be_empty
  end

  it 'does not report an automatic handoff as human takeover' do
    conversation.bot_handoff!
    expect(conversation.captain_decisions.where(kind: %w[human_control disengage])).to be_empty
  end
end
