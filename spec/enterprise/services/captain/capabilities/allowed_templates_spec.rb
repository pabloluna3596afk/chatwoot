require 'rails_helper'

RSpec.describe Captain::Capabilities::AllowedTemplates do
  let(:inbox) { instance_double(Inbox, id: 12, channel_type: 'Channel::Whatsapp') }
  let(:captain_inboxes) do
    instance_double(ActiveRecord::Associations::CollectionProxy, includes: [instance_double(CaptainInbox, inbox: inbox)])
  end
  let(:assistant) do
    instance_double(
      Captain::Assistant,
      config: { 'messaging' => { 'inboxes' => entries } },
      captain_inboxes: captain_inboxes,
      allow_paid_templates?: paid_templates
    )
  end
  let(:paid_templates) { true }
  let(:entries) { [{ 'inbox_id' => 12, 'enabled' => true, 'templates' => [{ 'name' => 'welcome' }] }] }

  it 'returns needs_setup when no template is selected' do
    allow(assistant).to receive(:config).and_return({ 'messaging' => { 'inboxes' => [] } })
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'no_items', count: nil)
  end

  it 'returns off when templates are selected but their inbox switch is off' do
    allow(assistant).to receive(:config).and_return({ 'messaging' => { 'inboxes' => entries.map { |entry| entry.merge('enabled' => false) } } })
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'disabled', count: nil)
  end

  it 'returns off when paid templates are not allowed' do
    allow(assistant).to receive(:allow_paid_templates?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'templates_off', count: nil)
  end

  it 'returns ready when templates are allowed in the inbox' do
    expect(described_class.new(assistant, inbox).call).to eq(status: 'ready', reason: nil, count: nil)
  end
end
