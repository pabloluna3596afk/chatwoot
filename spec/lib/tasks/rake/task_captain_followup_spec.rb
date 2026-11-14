require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['captain:followup:close_stale'] }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pilot) { true }
  let(:mode) { 'evaluated' }
  let(:assistant) { create(:captain_assistant, account: account, auto_resolve_mode: mode) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }

  before do
    account.enable_features!('captain_pilot') if pilot
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

  it 'never sends a public message' do
    account.enable_features!('captain_integration_v2')
    assistant.update!(send_inactivity_resolution_message: true)
    expect(conversation.can_reply?).to be(true)

    with_modified_env(DRY_RUN: 'false') do
      expect { task.invoke }.not_to(change { conversation.messages.where(private: false, message_type: :outgoing).count })
    end

    expect(conversation.reload).to be_resolved
    expect(conversation.messages.where(private: true).last.content).to eq(
      I18n.t('captain.notes.closed_unanswered', assistant: assistant.name, locale: account.locale)
    )
  end

  context 'without a pilot account' do
    let(:pilot) { false }

    it 'does not close or write a note' do
      with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
      expect(conversation.reload).to be_pending
      expect(conversation.messages.where(private: true)).to be_empty
    end
  end

  %w[legacy disabled].each do |resolution_mode|
    context "with mode #{resolution_mode}" do
      let(:mode) { resolution_mode }

      it 'does not close or write a note' do
        with_modified_env(DRY_RUN: 'false') { expect { task.invoke }.not_to output.to_stdout }
        expect(conversation.reload).to be_pending
        expect(conversation.messages.where(private: true)).to be_empty
      end
    end
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
