require 'rails_helper'

RSpec.describe Captain::Copilot::ChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  before do
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-key' }
  end

  it 'registers the read-only data and metadata tools' do
    service = described_class.new(assistant, user_id: user.id)
    tool_names = service.instance_variable_get(:@tools).map(&:name)

    expect(tool_names).to include(
      'get_data', 'summarize_conversation', 'list_labels', 'list_agents', 'list_teams', 'list_custom_attributes',
      'describe_schema'
    )
  end

  it 'registers propose_action only for an owned persisted thread' do
    thread = create(:captain_copilot_thread, account: account, user: user, assistant: assistant)
    service = described_class.new(assistant, user_id: user.id, copilot_thread_id: thread.id)

    expect(service.instance_variable_get(:@tools).map(&:name)).to include('propose_action')
  end

  it 'instructs Copilot to retry empty filtered searches and order latest conversations' do
    service = described_class.new(assistant, user_id: user.id)
    prompt = service.instance_variable_get(:@messages).map { |message| message[:content] }.join("\n")

    expect(prompt).to include('repeat exactly once without filters')
    expect(prompt).to include('order_by=last_activity_at, direction=desc, limit=1')
    expect(prompt).to include('UNTRUSTED_DATA_BEGIN')
    expect(prompt).to include('approved only by pressing Approve')
    expect(prompt).to include('do not create another proposal')
  end

  it 'does not persist or return a proposal claim unless its proposal id exists' do
    thread = create(:captain_copilot_thread, account: account, user: user, assistant: assistant)
    service = described_class.new(assistant, user_id: user.id, copilot_thread_id: thread.id)
    assistant_message = thread.copilot_messages.create!(message_type: :assistant, message: { content: 'Prepared a proposal.' })
    result = { 'content' => 'I prepared a proposal for you.' }
    proposal_tool = service.instance_variable_get(:@tools).find { |tool| tool.name == 'propose_action' }

    corrected = Captain::Copilot::ProposalClaimValidator.call(thread: thread, proposal_tool: proposal_tool, result: result)

    expect(corrected['content']).to include('No hay una propuesta creada')
    expect(assistant_message.reload.message['content']).to eq(corrected['content'])
    expect(thread.copilot_action_items).to be_empty
  end

  it 'removes a failed proposal step so a later retry is not shown as a final failure' do
    thread = create(:captain_copilot_thread, account: account, user: user, assistant: assistant)
    service = described_class.new(assistant, user_id: user.id, copilot_thread_id: thread.id)
    failed_step = thread.copilot_messages.create!(
      message_type: :assistant_thinking,
      message: { content: 'Using propose_action', function_name: 'propose_action', tool_status: 'in_progress' }
    )
    tool_call = Struct.new(:name).new('propose_action')
    service.instance_variable_set(:@pending_tool_calls, [{ tool_call: tool_call, thinking_message: failed_step }])

    service.send(:handle_tool_result, error: 'payload must be an integer')

    expect(thread.copilot_messages.exists?(id: failed_step.id)).to be false
    expect(thread.copilot_messages.where(message_type: :assistant_thinking)).to be_empty
  end
end
