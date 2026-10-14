require 'rails_helper'

RSpec.describe Calendar::AppointmentAttributes::BackfillJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) { create(:calendar_connection, account: account) }

  before do
    Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: Calendar::AppointmentAttributes::Definitions::TYPES.keys)
  end

  it 'enqueues each linked contact once, including contacts with only cancelled or deleted appointments' do
    other = create(:contact, account: account)
    unlinked = create(:contact, account: account)
    create_list(:calendar_event, 2, calendar_connection: connection, contact: contact)
    create(:calendar_event, calendar_connection: connection, contact: other, appointment_status: 'cancelled', deleted_at: Time.current)
    create(:calendar_event, calendar_connection: connection)
    create(:calendar_event, contact: create(:contact))
    allow(Calendar::AppointmentAttributes::UpdateJob).to receive(:perform_later)

    described_class.perform_now(account.id)

    expect(Calendar::AppointmentAttributes::UpdateJob).to have_received(:perform_later).with(account.id, contact.id).once
    expect(Calendar::AppointmentAttributes::UpdateJob).to have_received(:perform_later).with(account.id, other.id).once
    expect(Calendar::AppointmentAttributes::UpdateJob).not_to have_received(:perform_later).with(account.id, unlinked.id)
    expect(Calendar::AppointmentAttributes::UpdateJob).to have_received(:perform_later).exactly(2).times
  end

  it 'fills existing appointments when the queued contact jobs run' do
    create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 1.day.from_now, summary: 'Existing')

    perform_enqueued_jobs(only: Calendar::AppointmentAttributes::UpdateJob) { described_class.perform_now(account.id) }

    expect(contact.reload.custom_attributes).to include('total_citas' => 1, 'proxima_cita_titulo' => 'Existing')
  end

  it 'does not enqueue when disabled before execution' do
    account.update!(appointment_attributes: { 'enabled_keys' => [] })

    expect { described_class.perform_now(account.id) }.not_to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob)
  end

  it 'ignores deleted accounts' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
