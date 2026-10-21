require 'rails_helper'

RSpec.describe ActionCableBroadcastJob do
  it 'delivers appointment invalidation only to the owning account channel, without event details' do
    account = create(:account)
    other_account = create(:account)
    contact = create(:contact, account: account)
    connection = create(:calendar_connection, account: account)
    allow(ActionCable.server).to receive(:broadcast)

    perform_enqueued_jobs(only: described_class) do
      create(:calendar_event, calendar_connection: connection, contact: contact, summary: 'Private appointment')
    end

    expect(ActionCable.server).to have_received(:broadcast).with(
      "account_#{account.id}",
      { event: 'calendar.events_changed', data: { account_id: account.id, contact_ids: [contact.id] } }
    )
    expect(ActionCable.server).not_to have_received(:broadcast).with("account_#{other_account.id}", anything)
  end
end
