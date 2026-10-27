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

    expect(tool_names).to include('get_data', 'list_labels', 'list_custom_attributes')
  end
end
