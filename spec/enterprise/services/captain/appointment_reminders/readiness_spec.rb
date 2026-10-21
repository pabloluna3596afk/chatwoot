require 'rails_helper'

RSpec.describe Captain::AppointmentReminders::Readiness do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:reference) { { 'name' => 'reminder', 'language' => 'es', 'processed_params' => { 'body' => { '1' => '{{ contact.name }}' } } } }
  let(:entry) { { 'name' => 'reminder', 'language' => 'es', 'status' => 'approved', 'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}' }] } }
  let(:readiness) { described_class.new(assistant, inbox) }

  before do
    allow(assistant).to receive_messages(appointments_active_in?: true, allow_paid_templates?: true)
    allow(inbox).to receive(:channel_type).and_return('Channel::Whatsapp')
    allow(assistant).to receive(:appointments).and_return(Captain::AppointmentsSettings.new('template_reminder' => reference))
    allow(Captain::TemplateMessage).to receive(:approved).with(inbox, reference).and_return(entry)
  end

  it 'reports structural readiness without resolving customer values or sending' do
    expect(Variables::Resolver).not_to receive(:new)
    expect(readiness.to_h).to include(status: 'ready', missing: [], inbox_id: inbox.id)
  end

  it 'reports inactive Captain before template eligibility' do
    allow(assistant).to receive(:appointments_active_in?).with(inbox).and_return(false)
    expect(readiness.to_h[:status]).to eq('disabled')
  end

  it 'reports both reminders disabled' do
    allow(assistant).to receive(:appointments).and_return(Captain::AppointmentsSettings.new(
                                                            'reminder_1' => { 'enabled' => false }, 'reminder_2' => { 'enabled' => false }
                                                          ))
    expect(readiness.to_h[:status]).to eq('disabled')
  end

  it 'reports incompatible channels outside their reply window' do
    allow(inbox).to receive(:channel_type).and_return('Channel::FacebookPage')
    expect(readiness.outside_window_reason).to eq('not_sent_channel')
  end

  it 'reports payment permission without enabling it' do
    allow(assistant).to receive(:allow_paid_templates?).and_return(false)
    expect(readiness.outside_window_reason).to eq('not_sent_window')
    expect(assistant.config).not_to have_key('allow_paid_templates')
  end

  it 'reports no selected template' do
    allow(assistant).to receive(:appointments).and_return(Captain::AppointmentsSettings.new)
    expect(readiness.outside_window_reason).to eq('no_template')
  end

  it 'checks approval separately for each inbox' do
    allow(Captain::TemplateMessage).to receive(:approved).with(inbox, reference).and_return(nil)
    expect(readiness.outside_window_reason).to eq('template_unavailable')
  end

  it 'reports incomplete bindings with the same reason as the sender' do
    entry['components'].first['text'] = 'Hola {{1}}, {{2}}'
    expect(readiness.to_h).to include(status: 'template_changed', missing: ['body.2'])
  end

  it 'uses the historical numbered bindings when mappings did not exist' do
    reference.delete('processed_params')
    allow(assistant).to receive(:appointments).and_return(Captain::AppointmentsSettings.new('template_reminder' => reference))
    expect(readiness.to_h[:status]).to eq('ready')
    expect(reference).not_to have_key('processed_params')
  end
end
