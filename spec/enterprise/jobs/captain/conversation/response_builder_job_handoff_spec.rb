require 'rails_helper'

RSpec.describe Captain::Conversation::ResponseBuilderJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, out_of_office_message: 'We are closed.') }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, ai_assignee: assistant) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService, handoff_completed?: true, response_discarded?: false) }
  let(:run_result) do
    Agents::RunResult.new(output: {}, context: { state: tool_context.state, conversation_history: [] })
  end

  before do
    put_account_on_plan(account)
    account.enable_features!(:captain_integration, :captain_integration_v2)
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    allow(runner).to receive(:last_run_result).and_return(run_result)
    allow(runner).to receive(:generate_response) do
      Captain::Tools::HandoffTool.new(assistant).perform(tool_context, reason_category: 'customer_request')
      { 'response' => 'conversation_handoff', 'handoff_tool_called' => true }
    end
  end

  it 'sends only the out-of-office message after the real handoff tool and captures the single minimal note' do
    inbox.update!(working_hours_enabled: true)
    inbox.working_hours.each { |hours| hours.update!(closed_all_day: true, open_all_day: false) }

    described_class.perform_now(conversation, assistant)

    expect(conversation.messages.where(private: false).pluck(:content)).to eq(['We are closed.'])
    note = conversation.messages.where(private: true).sole
    expect(note.content).to eq(I18n.t('captain.notes.handoff_without_reason', assistant: assistant.name))
    expect(note.content_attributes['captain_handoff']).to eq('reason_category' => 'customer_request', 'source' => 'tool')
    expect(Captain::AgentSession.where(subject: conversation).sole.result).to eq(note)
  end

  it 'sends the handoff message inside business hours after the real tool' do
    waiting_since = 10.minutes.ago
    conversation.update!(waiting_since: waiting_since)

    described_class.perform_now(conversation, assistant)

    expect(conversation.messages.where(private: false).pluck(:content)).to eq([I18n.t('conversations.captain.handoff')])
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.reload.waiting_since).to be_within(1.second).of(waiting_since)
  end

  it 'falls back once after the real tool when the out-of-office send saves no record' do
    inbox.update!(working_hours_enabled: true)
    inbox.working_hours.each { |hours| hours.update!(closed_all_day: true, open_all_day: false) }
    allow(MessageTemplates::Template::OutOfOffice).to receive(:perform_if_applicable).and_return(true)

    described_class.perform_now(conversation, assistant)

    expect(conversation.messages.where(private: false).pluck(:content)).to eq([I18n.t('conversations.captain.handoff')])
    expect(conversation.messages.where(private: true).count).to eq(1)
  end
end
