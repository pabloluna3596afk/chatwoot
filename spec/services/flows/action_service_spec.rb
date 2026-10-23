require 'rails_helper'

RSpec.describe Flows::ActionService do
  let(:conversation) { create(:conversation) }
  let(:account) { conversation.account }
  let(:flow) { Flow.create!(account: account, name: 'Variables') }
  let(:run) { FlowRun.create!(account: account, conversation: conversation, flow: flow, variables: { x: 'stored' }) }
  let(:service) { described_class.new(conversation: conversation, flow_run: run) }

  it 'uses the shared snooze duration' do
    travel_to(Time.zone.local(2026, 10, 23, 12)) do
      service.execute(action_name: 'snooze_conversation', action_params: { duration: 2, unit: 'hours' })

      expect(conversation.reload.status).to eq('snoozed')
      expect(conversation.snoozed_until).to eq(2.hours.from_now)
    end
  end

  it 'reads flow values when creating private notes' do
    service.execute(action_name: 'add_private_note', action_params: ['{{ flow.x }}'])

    expect(conversation.messages.outgoing.last).to have_attributes(content: 'stored', private: true)
  end

  it 'uses flow values with the shared attribute writer' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'flow_value',
                                         attribute_display_type: 'text')
    service.execute(action_name: 'update_contact_custom_attribute', action_params: [{ attribute_key: 'flow_value', value: '{{ flow.x }}' }])

    expect(conversation.contact.reload.custom_attributes['flow_value']).to eq('stored')
  end

  it 'passes the explicit run to notification rendering' do
    team = create(:team, account: account)
    mail = instance_double(ActionMailer::MessageDelivery, deliver_now: nil)
    allow(TeamNotifications::AutomationNotificationMailer).to receive(:conversation_creation).and_return(mail)

    service.execute(action_name: 'send_email_to_team', action_params: [{ team_ids: [team.id], message: '{{ flow.x }}' }])

    expect(TeamNotifications::AutomationNotificationMailer).to have_received(:conversation_creation)
      .with(conversation, team, '{{ flow.x }}', flow_run: run)
  end
end
