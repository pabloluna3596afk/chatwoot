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

    expect(tool_names).to include('get_data', 'summarize_conversation', 'list_labels', 'list_custom_attributes', 'describe_schema')
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
  end
end
