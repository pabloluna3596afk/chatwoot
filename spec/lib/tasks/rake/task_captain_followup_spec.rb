require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['captain:followup:close_stale'] }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, unanswered_action: 'close') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    create(:message, conversation: conversation, sender: assistant, message_type: :outgoing, created_at: 4.days.ago)
    conversation.update!(last_activity_at: 4.days.ago)
    task.reenable
  end

  it 'lists without changing anything by default' do
    with_modified_env(DRY_RUN: nil) do
      expect { task.invoke }.to output(/Would close conversation_id=#{conversation.id}/).to_stdout
    end
    expect(conversation.reload).to be_pending
    expect(conversation.messages.where(private: true)).to be_empty
  end

  it 'closes when DRY_RUN=false' do
    with_modified_env(DRY_RUN: 'false') do
      expect { task.invoke }.to output(/Closed conversation_id=#{conversation.id}/).to_stdout
    end
    expect(conversation.reload).to be_resolved
    expect(conversation.additional_attributes['captain_followup']).to include('assistant_id' => assistant.id)
  end

  %w[handoff leave_open].each do |action|
    it "does not close assistants configured as #{action}" do
      assistant.update!(unanswered_action: action)
      with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
      expect(conversation.reload).to be_pending
      expect(conversation.messages.where(private: true)).to be_empty
    end
  end

  it 'does not close existing assistants without a policy' do
    assistant.update!(config: assistant.config.except('unanswered_action'))
    with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
    expect(conversation.reload).to be_pending
  end

  it 'does not close a conversation with recent activity' do
    conversation.update!(last_activity_at: 1.day.ago)
    with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
    expect(conversation.reload).to be_pending
  end

  it 'does not close when the customer spoke last' do
    create(:message, conversation: conversation, sender: conversation.contact, message_type: :incoming, created_at: 73.hours.ago)
    conversation.update!(last_activity_at: 73.hours.ago)
    with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
    expect(conversation.reload).to be_pending
  end
end
