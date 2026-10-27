require 'rails_helper'

describe Conversations::AssignmentService do
  def activity_job_count
    enqueued_jobs.count { |job| job[:job] == Conversations::ActivityMessageJob }
  end

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
      described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
                                                               .and change { activity_job_count }.by(1)

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: nil, ai_assignee: assistant)
    expect(conversation.assignment_driven_status).to be(false)
  end

  it 'schedules the latest unanswered customer message once on Captain assignment' do
    message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, private: false)
    scheduler = instance_double(Captain::Conversation::ResponseSchedulerService, perform: true)
    expect(Captain::Conversation::ResponseSchedulerService).to receive(:new).with(message: message).once.and_return(scheduler)

    described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform

    expect(conversation.reload.additional_attributes).to include(
      'captain_assignment_message_id' => message.id,
      'captain_assignment_response_message_id' => message.id
    )
  end

  it 'does not schedule when a public outgoing message follows the customer message' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, private: false)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: false)
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new)

    described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
  end

  it 'does not schedule when the WhatsApp reply window is closed' do
    channel = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
    whatsapp_inbox = Inbox.find_by!(channel: channel)
    create(:captain_inbox, inbox: whatsapp_inbox, captain_assistant: assistant)
    whatsapp_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, status: :open)
    create(:message, conversation: whatsapp_conversation, account: account, inbox: whatsapp_inbox, message_type: :incoming,
                     private: false, created_at: 25.hours.ago)
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new)

    described_class.new(conversation: whatsapp_conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
  end

  it 'does not schedule when Captain is paused for quota exhaustion' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, private: false)
    allow(Llm::Config).to receive(:api_key_configured?).and_return(true)
    account.update!(limits: { 'captain_responses' => 0 })
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new)

    described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
  end

  it 'does not schedule when the contact is outside Captain audience' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, private: false)
    assistant.update!(config: assistant.config.merge('audience' => {
                                                       'attribute_key' => 'phone_number', 'filter_operator' => 'contains', 'values' => ['+593']
                                                     }))
    conversation.contact.update!(phone_number: '+14155552671')
    expect(Captain::Conversation::ResponseSchedulerService).not_to receive(:new)

    described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
  end

  it 'records only the human assignment when a person takes over from Captain' do
    conversation.update!(assignee: nil, ai_assignee: assistant, status: :pending)
    content = I18n.t('conversations.activity.assignee.assigned', assignee_name: agent.name, user_name: actor.name)

    expect do
      described_class.new(conversation: conversation.reload, assignee_id: agent.id).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
                                                               .and change { activity_job_count }.by(1)

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
      described_class.new(conversation: conversation.reload, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
                                                               .and change { activity_job_count }.by(1)

    expect(conversation.reload).to have_attributes(status: 'pending', ai_assignee: assistant)
  end

  it 'records one assignment when a person replaces another person' do
    content = I18n.t('conversations.activity.assignee.assigned', assignee_name: other_agent.name, user_name: actor.name)

    expect do
      described_class.new(conversation: conversation.reload, assignee_id: other_agent.id).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(conversation, hash_including(content: content)).exactly(:once)
                                                               .and change { activity_job_count }.by(1)

    expect(conversation.reload).to have_attributes(status: 'open', assignee: other_agent)
  end

  it 'clears the assignment flag if saving fails' do
    conversation.reload
    allow(conversation).to receive(:with_lock).and_yield
    allow(conversation).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(conversation))

    expect do
      described_class.new(conversation: conversation, assignee_id: assistant.id, assignee_type: 'Captain::Assistant').perform
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(conversation.assignment_driven_status).to be(false)
  end
end
