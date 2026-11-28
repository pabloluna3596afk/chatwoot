require 'rails_helper'

RSpec.describe ActionCableBroadcastJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:stale_data) { { id: conversation.display_id, account_id: account.id, status: 'open' } }

  before do
    conversation.update!(status: :resolved)
    allow(ActionCable.server).to receive(:broadcast)
  end

  it 'refreshes a conversation event with the full payload for agents and the widget payload for widget sessions' do
    described_class.perform_now(['agent-token'], Events::Types::CONVERSATION_STATUS_CHANGED, stale_data,
                                widget_members: ['widget-token'], widget_data: stale_data)

    expect(ActionCable.server).to have_received(:broadcast).with(
      'agent-token',
      { event: Events::Types::CONVERSATION_STATUS_CHANGED, data: conversation.reload.push_event_data.merge(account_id: account.id) }
    )
    expect(ActionCable.server).to have_received(:broadcast).with(
      'widget-token',
      { event: Events::Types::CONVERSATION_STATUS_CHANGED, data: conversation.reload.widget_push_event_data.merge(account_id: account.id) }
    )
  end

  it 'sends the prebuilt payloads for events that are not refreshed' do
    widget_data = { id: 1, account_id: account.id }
    described_class.perform_now(['agent-token'], Events::Types::MESSAGE_CREATED, { id: 1, content: 'hi', account_id: account.id },
                                widget_members: ['widget-token'], widget_data: widget_data)

    expect(ActionCable.server).to have_received(:broadcast).with(
      'agent-token', { event: Events::Types::MESSAGE_CREATED, data: { id: 1, content: 'hi', account_id: account.id } }
    )
    expect(ActionCable.server).to have_received(:broadcast).with(
      'widget-token', { event: Events::Types::MESSAGE_CREATED, data: widget_data }
    )
  end

  it 'sends widget sessions their payload when there are no agent members' do
    described_class.perform_now([], Events::Types::CONVERSATION_STATUS_CHANGED, stale_data,
                                widget_members: ['widget-token'], widget_data: stale_data)

    expect(ActionCable.server).to have_received(:broadcast).once.with(
      'widget-token',
      { event: Events::Types::CONVERSATION_STATUS_CHANGED, data: conversation.reload.widget_push_event_data.merge(account_id: account.id) }
    )
  end

  it 'keeps translation attributes private when refreshing a Client API conversation' do
    message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                               content_attributes: { translations: { en: 'Hello' }, items: [{ title: 'Option' }] })

    described_class.perform_now(['client-token'], Events::Types::CONVERSATION_UPDATED, stale_data, public_contact_payload: true)

    expect(ActionCable.server).to have_received(:broadcast).with(
      'client-token',
      { event: Events::Types::CONVERSATION_UPDATED,
        data: conversation.reload.push_event_data.merge(
          account_id: account.id, messages: [message.reload.push_event_data.merge(content_attributes: message.public_content_attributes)]
        ) }
    )
  end

  it 'preserves the original automatic assignment while refreshing the conversation' do
    data = stale_data.merge(automatic_assignment: true, meta: { assignee: { id: 42 }, assignee_type: 'User' }, updated_at: 123.0)

    described_class.perform_now(['agent-token'], Events::Types::ASSIGNEE_CHANGED, data)

    expect(ActionCable.server).to have_received(:broadcast).with(
      'agent-token',
      { event: Events::Types::ASSIGNEE_CHANGED,
        data: conversation.reload.push_event_data.merge(
          account_id: account.id, assignment: { automatic: true, assignee_id: 42, assignee_type: 'User', updated_at: 123.0 }
        ) }
    )
  end
end
