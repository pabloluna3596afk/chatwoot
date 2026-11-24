require 'rails_helper'

RSpec.describe Calendar::AppointmentAttributes::Updater do
  subject(:updater) { described_class.new(contact: contact) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'other' => 'keep' }) }
  let(:connection) { create(:calendar_connection, account: account) }
  let(:event_attributes) { { calendar_connection: connection, contact: contact } }
  let(:keys) { Calendar::AppointmentAttributes::Definitions::TYPES.keys }

  before { Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: keys) }

  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00-05:00')) { example.run } }

  it 'recalculates UTC dates, next title and the total across calendars and booking sources' do
    create(:calendar_event, **event_attributes, start_at: 3.days.ago)
    create(:calendar_event, **event_attributes, start_at: 1.day.ago)
    create(:calendar_event, **event_attributes, start_at: 1.hour.from_now, summary: 'Next', booking_source: 'ai')
    create(:calendar_event, contact: contact, calendar_connection: create(:calendar_connection, account: account), start_at: 2.days.from_now)
    create(:calendar_event, **event_attributes, start_at: 30.minutes.from_now, appointment_status: 'cancelled')
    create(:calendar_event, **event_attributes, start_at: 30.minutes.ago, appointment_status: 'cancelled')
    create(:calendar_event, **event_attributes, start_at: 10.minutes.ago, deleted_at: Time.current)
    create(:calendar_event, calendar_connection: connection, start_at: 5.minutes.from_now)

    updater.perform

    expect(contact.reload.custom_attributes).to eq(
      'other' => 'keep', 'ultima_cita' => '2030-01-13T17:00:00Z', 'proxima_cita' => '2030-01-14T18:00:00Z',
      'proxima_cita_titulo' => 'Next', 'total_citas' => 4, 'estado_proxima_cita' => 'none', 'citas_canceladas' => 2
    )
  end

  it 'clears obsolete dates and title and sets zero when all appointments are cancelled or deleted' do
    contact.update!(custom_attributes: keys.index_with { 'old' })
    create(:calendar_event, **event_attributes, appointment_status: 'cancelled')
    create(:calendar_event, **event_attributes, deleted_at: Time.current)

    updater.perform

    expect(contact.reload.custom_attributes).to eq(
      'ultima_cita' => nil, 'proxima_cita' => nil, 'proxima_cita_titulo' => nil, 'total_citas' => 0,
      'estado_proxima_cita' => nil, 'citas_canceladas' => 1
    )
  end

  it 'includes an appointment starting now in the past and counts undated appointments' do
    create(:calendar_event, **event_attributes, start_at: Time.current)
    create(:calendar_event, **event_attributes, start_at: nil, end_at: nil)

    updater.perform

    expect(contact.reload.custom_attributes).to include('ultima_cita' => Time.current.utc.iso8601, 'proxima_cita' => nil, 'total_citas' => 2)
  end

  %w[none pending_confirmation confirmed rescheduled].each do |status|
    it "uses the same nearest appointment for its date, title and #{status} status" do
      create(:calendar_event, **event_attributes, start_at: 2.hours.from_now, appointment_status: 'confirmed')
      create(:calendar_event, **event_attributes, start_at: 30.minutes.from_now, appointment_status: 'cancelled')
      create(:calendar_event, **event_attributes, start_at: 1.hour.from_now, summary: 'Nearest', appointment_status: status)

      updater.perform

      expect(contact.reload.custom_attributes).to include(
        'proxima_cita' => 1.hour.from_now.utc.iso8601, 'proxima_cita_titulo' => 'Nearest', 'estado_proxima_cita' => status
      )
    end
  end

  it 'clears the next status and sets both counts to zero for a contact without appointments' do
    contact.update!(custom_attributes: { 'estado_proxima_cita' => 'confirmed', 'citas_canceladas' => 9 })

    updater.perform

    expect(contact.reload.custom_attributes).to include(
      'proxima_cita' => nil, 'estado_proxima_cita' => nil, 'total_citas' => 0, 'citas_canceladas' => 0
    )
  end

  it 'counts only cancelled appointments for this contact and account, including soft deleted cancellations' do
    create(:calendar_event, **event_attributes, appointment_status: 'cancelled')
    create(:calendar_event, **event_attributes, appointment_status: 'cancelled', deleted_at: Time.current)
    create(:calendar_event, **event_attributes, appointment_status: 'confirmed')
    create(:calendar_event, calendar_connection: connection, contact: create(:contact, account: account), appointment_status: 'cancelled')
    create(:calendar_event, contact: contact, appointment_status: 'cancelled')

    updater.perform

    expect(contact.reload.custom_attributes).to include('citas_canceladas' => 2, 'total_citas' => 1)
  end

  it 'recalculates both new attributes through the job after status changes and cancellation' do
    event = create(:calendar_event, **event_attributes, start_at: 1.day.from_now, appointment_status: 'pending_confirmation')
    updater.perform

    %w[confirmed rescheduled cancelled].each do |status|
      expect { event.update!(appointment_status: status) }
        .to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(account.id, contact.id).at(:no_wait)
      perform_enqueued_jobs(only: Calendar::AppointmentAttributes::UpdateJob, at: Time.current)

      expect(contact.reload.custom_attributes).to include(
        'estado_proxima_cita' => (status == 'cancelled' ? nil : status),
        'citas_canceladas' => (status == 'cancelled' ? 1 : 0), 'total_citas' => (status == 'cancelled' ? 0 : 1)
      )
    end
  end

  it 'does not overwrite a new attribute whose definition now has an incompatible type' do
    account.custom_attribute_definitions.find_by!(attribute_key: 'citas_canceladas').update!(attribute_display_type: :text)
    contact.update!(custom_attributes: { 'citas_canceladas' => 'keep' })

    updater.perform

    expect(contact.reload.custom_attributes).to include('citas_canceladas' => 'keep', 'estado_proxima_cita' => nil)
  end

  it 'only updates selected compatible definitions' do
    account.update!(appointment_attributes: { 'enabled_keys' => %w[ultima_cita total_citas] })
    account.custom_attribute_definitions.find_by!(attribute_key: 'ultima_cita').update!(attribute_display_type: :text)
    contact.update!(custom_attributes: { 'ultima_cita' => 'keep', 'proxima_cita' => 'keep', 'total_citas' => 9 })

    updater.perform

    expect(contact.reload.custom_attributes).to eq('ultima_cita' => 'keep', 'proxima_cita' => 'keep', 'total_citas' => 0)
  end

  it 'does not write again when computed values have not changed' do
    updater.perform

    travel 1.minute

    expect { updater.perform }.not_to(change { contact.reload.updated_at })
  end

  it 'ignores missing contacts' do
    expect { described_class.new(contact: nil).perform }.not_to raise_error
  end

  it 'preserves values when the account is disabled after the job was queued' do
    account.update!(appointment_attributes: { 'enabled_keys' => [] })

    expect { updater.perform }.not_to(change { contact.reload.custom_attributes })
  end
end
