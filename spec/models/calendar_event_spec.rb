require 'rails_helper'

RSpec.describe CalendarEvent do
  let(:contact) { create(:contact) }
  let(:connection) { create(:calendar_connection, account: contact.account) }
  let(:event) { create(:calendar_event, calendar_connection: connection, contact: contact) }

  it 'enqueues a contact update after creation' do
    expect { event }.to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'refreshes the contact right after a future appointment starts' do
    freeze_time do
      start = 2.days.from_now
      expect { create(:calendar_event, calendar_connection: connection, contact: contact, start_at: start, end_at: start + 1.hour) }
        .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id).at(start + 1.minute)
    end
  end

  it 'does not enqueue for events without a linked contact' do
    expect { create(:calendar_event, calendar_connection: connection) }.not_to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob)
  end

  it 'enqueues after rescheduling' do
    event

    expect { event.update!(start_at: 2.days.from_now) }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'enqueues after renaming' do
    event

    expect { event.update!(summary: 'Changed') }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'enqueues after cancellation' do
    event

    expect { event.update!(appointment_status: 'cancelled') }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'enqueues after soft deletion' do
    event

    expect { event.update!(deleted_at: Time.current) }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'enqueues after hard deletion' do
    event

    expect { event.destroy! }.to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'updates both contacts when the linked contact changes' do
    event
    other = create(:contact, account: contact.account)

    expect { event.update!(contact: other) }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
      .and have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, other.id)
  end

  it 'updates the former contact when it is unlinked' do
    event

    expect { event.update!(contact: nil) }
      .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(contact.account_id, contact.id)
  end

  it 'does not enqueue for unrelated updates' do
    event

    expect { event.update!(etag: 'new-etag') }.not_to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob)
  end

  it 'does not enqueue when the transaction rolls back' do
    event

    expect do
      described_class.transaction(requires_new: true) do
        event.update!(summary: 'Rolled back')
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob)
  end
end
