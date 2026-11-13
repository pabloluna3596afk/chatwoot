require 'rails_helper'

RSpec.describe Captain::Tools::BasePublicTool do
  let(:assistant) { create(:captain_assistant) }
  let(:conversation) { create(:conversation, account: assistant.account) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }
  let(:tool) { described_class.new(assistant) }

  before do
    assistant.account.enable_features!(:captain_integration_v2)
    allow(tool).to receive(:perform).and_return('done')
  end

  after { Captain::Assistant::TransientErrors.reset!(conversation.id) }

  it 'marks the attempt when a tool with side effects runs' do
    tool.execute(tool_context)

    expect(Captain::Assistant::TransientErrors.side_effect_ran?(conversation.id)).to be true
  end

  it 'does not mark it for the knowledge lookup' do
    lookup = Captain::Tools::FaqLookupTool.new(assistant)
    allow(lookup).to receive(:perform).and_return('knowledge')
    lookup.execute(tool_context, query: 'hours')

    expect(Captain::Assistant::TransientErrors).not_to be_side_effect_ran(conversation.id)
  end

  it 'does not mark it for a GET custom tool and marks it for a POST one' do
    custom_tool = build(:captain_custom_tool, account: assistant.account, http_method: 'GET')
    http_tool = Captain::Tools::HttpTool.new(assistant, custom_tool)
    allow(http_tool).to receive(:perform).and_return('ok')
    http_tool.execute(tool_context)
    expect(Captain::Assistant::TransientErrors).not_to be_side_effect_ran(conversation.id)

    custom_tool.http_method = 'POST'
    http_tool.execute(tool_context)
    expect(Captain::Assistant::TransientErrors.side_effect_ran?(conversation.id)).to be true
  end

  it 'marks it in V1 too' do
    assistant.account.disable_features!(:captain_integration_v2)
    tool.execute(tool_context)

    expect(Captain::Assistant::TransientErrors.side_effect_ran?(conversation.id)).to be true
  end
end
