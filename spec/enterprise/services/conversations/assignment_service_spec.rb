require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:actor) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:other_assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent) }

  before do
    account.enable_features!('captain_integration')
    conversation
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    Current.user = actor
  end

  after { Current.reset }

  it 'records only the Captain assignment when handing a person-owned conversation to Captain' do
    content = I18n.t('conversations.activity.ai_assignee.assigned', assistant: assistant.name, actor: actor.name)

    expect do
      described_class.new(conversation: conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
      .and change { enqueued_jobs.count { |job| job[:job] == Conversations::ActivityMessageJob } }.by(1)

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: nil, ai_assignee: assistant)
    expect(conversation.assignment_driven_status).to be(false)
  end

  it 'records only the human assignment when a person takes over from Captain' do
    conversation.update!(assignee: nil, ai_assignee: assistant, status: :pending)
    content = I18n.t('conversations.activity.assignee.assigned', assignee_name: agent.name, user_name: actor.name)

    expect do
      described_class.new(conversation: conversation, assignee_id: agent.id).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
      .and change { enqueued_jobs.count { |job| job[:job] == Conversations::ActivityMessageJob } }.by(1)

    expect(conversation.reload).to have_attributes(status: 'open', assignee: agent, ai_assignee: nil)
    expect(conversation.assignment_driven_status).to be(false)
    expect { conversation.update!(status: :resolved) }.to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: I18n.t('conversations.activity.status.resolved', user_name: actor.name,
                                                                                              status_label: account.resolved_status_label_word)))
  end

  it 'records one assignment when Captain B replaces Captain A' do
    conversation.update!(assignee: nil, ai_assignee: other_assistant, status: :pending)
    content = I18n.t('conversations.activity.ai_assignee.assigned', assistant: assistant.name, actor: actor.name)

    expect do
      described_class.new(conversation: conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
      .and change { enqueued_jobs.count { |job| job[:job] == Conversations::ActivityMessageJob } }.by(1)

    expect(conversation.reload).to have_attributes(status: 'pending', ai_assignee: assistant)
  end

  it 'records one assignment when a person replaces another person' do
    content = I18n.t('conversations.activity.assignee.assigned', assignee_name: other_agent.name, user_name: actor.name)

    expect do
      described_class.new(conversation: conversation, assignee_id: other_agent.id).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
      .and change { enqueued_jobs.count { |job| job[:job] == Conversations::ActivityMessageJob } }.by(1)

    expect(conversation.reload).to have_attributes(status: 'open', assignee: other_agent)
  end

  it 'clears the assignment flag if saving fails' do
    allow(conversation).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(conversation))

    expect do
      described_class.new(conversation: conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(conversation.assignment_driven_status).to be(false)
  end
end
