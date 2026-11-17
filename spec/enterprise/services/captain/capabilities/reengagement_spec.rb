require 'rails_helper'

RSpec.describe Captain::Capabilities::Reengagement do
  let(:inbox) { instance_double(Inbox, id: 12, channel_type: 'Channel::Whatsapp') }
  let(:followup) { instance_double(Captain::FollowupSettings, reengagement_enabled?: enabled, reengagement_template: template) }
  let(:assistant) do
    instance_double(
      Captain::Assistant,
      captain_inboxes: instance_double(ActiveRecord::Associations::CollectionProxy, includes: [instance_double(CaptainInbox, inbox: inbox)]),
      followup: followup,
      allow_paid_templates?: paid_templates
    )
  end
  let(:enabled) { true }
  let(:paid_templates) { true }
  let(:template) { { 'name' => 'welcome', 'language' => 'es' } }

  it 'returns off when re-engagement is disabled' do
    allow(followup).to receive(:reengagement_enabled?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'disabled', count: nil)
  end

  it 'returns off when paid templates are disabled' do
    allow(assistant).to receive(:allow_paid_templates?).and_return(false)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'off', reason: 'templates_off', count: nil)
  end

  it 'returns needs_setup when no template is selected or the template is unavailable' do
    allow(followup).to receive(:reengagement_template).and_return(nil)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'no_template', count: nil)

    allow(followup).to receive(:reengagement_template).and_return(template)
    allow(Captain::TemplateMessage).to receive(:approved).with(inbox, template).and_return(nil)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'needs_setup', reason: 'template_unavailable', count: nil)
  end

  it 'returns ready when the selected template is approved for the inbox' do
    allow(Captain::TemplateMessage).to receive(:approved).with(inbox, template).and_return(Object.new)
    expect(described_class.new(assistant, inbox).call).to eq(status: 'ready', reason: nil, count: nil)
  end
end
