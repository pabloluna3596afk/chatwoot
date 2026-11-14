require 'rails_helper'

RSpec.describe Captain::Tools::CustomHttpTool do
  subject(:tool) { described_class.new(assistant, custom_tool, conversation: conversation) }

  let(:assistant) { create(:captain_assistant) }
  let(:conversation) { create(:conversation, account: assistant.account) }
  let(:custom_tool) do
    create(:captain_custom_tool, account: assistant.account, assistant: assistant,
                                 endpoint_url: 'https://example.com/{{ contact.identifier }}', response_template: nil)
  end

  it 'executes the HTTP tool with the conversation context' do
    conversation.contact.update!(identifier: 'eval-customer')
    stub_request(:get, 'https://example.com/eval-customer').to_return(body: 'order confirmed')
    expect(tool.execute).to eq('order confirmed')
  end

  it 'reports invalid template input without sending an HTTP request' do
    custom_tool.update!(endpoint_url: 'https://example.com/{{ contact.custom_attribute.missing }}')
    expect(tool.execute).to include('Template rendering failed')
    expect(WebMock).not_to have_requested(:get, /example.com/)
  end

  it 'does not expose a conversation from another account' do
    other_conversation = create(:conversation)
    other_conversation.contact.update!(identifier: 'private-customer')
    foreign_tool = described_class.new(assistant, custom_tool, conversation: other_conversation)
    expect(foreign_tool.execute).to include('Template rendering failed')
    expect(WebMock).not_to have_requested(:get, /private-customer/)
  end
end
