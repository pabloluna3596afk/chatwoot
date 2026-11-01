require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::ProposeActionService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'administrator') }
  let(:contact) { create(:contact, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

  it 'creates at most three proposals per tool turn without executing them' do
    action_service = instance_double(Captain::Copilot::ActionItemService)
    allow(Captain::Copilot::ActionItemService).to receive(:new).with(thread: thread, user: user).and_return(action_service)
    pending_item = instance_double(CopilotActionItem, status: 'pending', id: 99)
    allow(action_service).to receive(:propose).and_return(pending_item)
    tool = described_class.new(assistant, copilot_thread: thread, user: user)

    3.times do
      expect(tool.execute(action: 'add_label', target: { 'type' => 'Contact', 'id' => 1 }, payload: { 'label_id' => 1 }))
        .to include(status: 'pending')
    end
    expect(tool.execute(action: 'add_label', target: { 'type' => 'Contact', 'id' => 1 }, payload: { 'label_id' => 1 }))
      .to include(error: 'At most three proposals are allowed per turn')
    expect(action_service).to have_received(:propose).exactly(3).times
  end

  it 'rejects unregistered and destructive actions without creating proposals' do
    tool = described_class.new(assistant, copilot_thread: thread, user: user)
    forbidden_actions = %w[delete_conversation delete_contact resolve send_message merge invented_action]

    forbidden_actions.each do |action|
      result = tool.execute(action: action, target: { 'type' => 'Conversation', 'id' => 1 }, payload: {})
      expect(result).to include(:error)
    end

    expect(thread.copilot_action_items).to be_empty
  end

  it 'exposes only registered action names in its schema' do
    tool = described_class.new(assistant, copilot_thread: thread, user: user)
    names = tool.parameters_schema.dig('properties', 'action', 'enum')
    payload_schemas = tool.parameters_schema.dig('properties', 'payload', 'oneOf')

    expect(names).to match_array(Captain::Copilot::ActionRegistry.all.map(&:action_name))
    expect(payload_schemas.map { |schema| schema['title'] }).to match_array(names)
    Captain::Copilot::ActionRegistry.all.each do |action_class|
      schema = payload_schemas.find { |candidate| candidate['title'] == action_class.action_name }
      expect(schema).to include(action_class.schema.deep_stringify_keys)
      expect(schema['examples']).to be_present
    end
  end

  it 'returns an actionable error for an invalid add-label payload' do
    tool = described_class.new(assistant, copilot_thread: thread, user: user)

    result = tool.execute(action: 'add_label', target: { 'type' => 'Contact', 'id' => contact.id },
                          payload: { 'label_name' => 'sales' })

    expect(result[:error]).to include('label_name', 'list_labels', 'label_id')
    expect(thread.copilot_action_items).to be_empty
  end
end
