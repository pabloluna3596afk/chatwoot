require 'rails_helper'

RSpec.describe TeamNotifications::AutomationNotificationMailer do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:conversation) { create(:conversation, account: account) }
  let(:team) { create(:team, account: account) }
  let(:mailer) { described_class.new }

  before do
    allow(mailer).to receive(:smtp_config_set_or_development?).and_return(true)
    allow(mailer).to receive(:send_mail_with_liquid)
  end

  it 'reproduces MV-13: renders custom_message before inserting it into the mail template' do
    conversation.contact.update!(identifier: 'exact-value')
    mailer.conversation_creation(conversation, team, 'Hello {{ contact.identifier }}')

    expect(mailer.send(:liquid_locals)[:custom_message]).to eq('Hello exact-value')
    expect(mailer).to have_received(:send_mail_with_liquid)
  end

  it 'renders the final email without leaving the original expression in custom_message' do
    create(:team_member, team: team, user: create(:user, account: account))
    conversation.contact.update!(identifier: 'final-email')
    with_modified_env SMTP_ADDRESS: 'smtp.example.com' do
      email = described_class.conversation_creation(conversation, team, 'Hello {{ contact.identifier }}').message
      expect(email.body.decoded).to include('Hello final-email')
      expect(email.body.decoded).not_to include('{{ contact.identifier }}')
    end
  end

  it 'renders flow variables only from the supplied run' do
    flow = Flow.create!(account: account, name: 'Mail')
    run = FlowRun.create!(account: account, conversation: conversation, flow: flow, variables: { x: 'saved' })
    mailer.conversation_creation(conversation, team, '{{ flow.x }}', flow_run: run)

    expect(mailer.send(:liquid_locals)[:custom_message]).to eq('saved')
  end

  it 'keeps inserted values literal rather than rendering them recursively' do
    conversation.contact.update!(identifier: '{{ contact.email }}')
    mailer.conversation_creation(conversation, team, '{{ contact.identifier }}')

    expect(mailer.send(:liquid_locals)[:custom_message]).to eq('{{ contact.email }}')
  end

  it 'omits incomplete notifications with a private diagnostic instead of sending blank text' do
    mailer.conversation_creation(conversation, team, 'Hello {{ contact.custom_attribute.absent }}')

    expect(mailer).not_to have_received(:send_mail_with_liquid)
    expect(conversation.messages.outgoing.last).to have_attributes(private: true)
    expect(conversation.messages.outgoing.last.content).to include('custom_message: missing')
  end

  it 'omits invalid Liquid and keeps legacy plain notifications' do
    mailer.conversation_creation(conversation, team, '{% if %}')
    expect(mailer).not_to have_received(:send_mail_with_liquid)
    mailer.conversation_creation(conversation, team, 'Plain notification')
    expect(mailer.send(:liquid_locals)[:custom_message]).to eq('Plain notification')
  end

  it 'uses the account timezone for notification dates' do
    travel_to Time.utc(2026, 10, 20, 2) do
      mailer.conversation_creation(conversation, team, '{{ date.today }}')
      expect(mailer.send(:liquid_locals)[:custom_message]).to eq('2026-10-19')
    end
  end
end
