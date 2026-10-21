require 'rails_helper'

RSpec.describe Calendar::AppointmentAttributes::Updater do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:connection) { create(:calendar_connection, account: account) }
  let(:keys) { Calendar::AppointmentAttributes::Definitions::TYPES.keys }

  around { |example| travel_to(Time.zone.parse('2030-01-14T12:00:00Z')) { example.run } }

  before { Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: keys) }

  it 'derives all four values through booking jobs' do
    create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 1.day.ago)
    expect do
      create(:calendar_event, calendar_connection: connection, contact: contact, start_at: 1.day.from_now, summary: 'Consultation')
    end.to have_enqueued_job(Calendar::AppointmentAttributes::UpdateJob).with(account.id, contact.id).at(:no_wait)
    perform_enqueued_jobs(only: Calendar::AppointmentAttributes::UpdateJob, at: Time.current)

    expect(contact.reload.custom_attributes).to include(
      'ultima_cita' => '2030-01-13T12:00:00Z', 'proxima_cita' => '2030-01-15T12:00:00Z',
      'proxima_cita_titulo' => 'Consultation', 'total_citas' => 2
    )
  end

  it 'exposes all four derivatives as read only to existing consumers' do
    definitions = account.custom_attribute_definitions.contact_attribute
    expect(definitions.map { |definition| Variables::Ownership.for(definition) }).to eq(Array.new(4, 'calendar'))
    entries = Variables::Catalog.new(account: account, surface: 'captain').as_json[:variables].select { |entry| keys.include?(entry[:key]) }
    expect(entries.size).to eq(4)
    expect(entries).to all(include(managedBy: 'calendar', writable: false, writeContexts: []))

    writer = Variables::Writer.new(account: account)
    contexts = %w[automation whatsapp_flow manual]
    keys.each do |key|
      contexts.each do |context|
        expect(writer.target("contact.custom_attribute.#{key}", context: context)).to be_nil
      end
      expect { writer.patch(scope: 'contact', current: contact.custom_attributes, values: { key => 'overwrite' }) }
        .to raise_error(ActionController::ParameterMissing)
      expect { writer.remove(scope: 'contact', current: contact.custom_attributes, keys: [key]) }
        .to raise_error(ActionController::ParameterMissing)
    end
  end
end
