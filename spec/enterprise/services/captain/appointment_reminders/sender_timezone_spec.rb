require 'rails_helper'

RSpec.describe Captain::AppointmentReminders::Sender do
  let(:account) { create(:account, locale: 'en', settings: { reporting_timezone: timezone }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { Captain::Tools::BookAppointmentTool.new(assistant) }
  let(:event) { build(:calendar_event, account: account, start_at: Time.utc(2031, 1, 1, 0, 30), summary: 'Consultation') }
  let(:reminder) { instance_double(Captain::AppointmentReminder, account: account, calendar_event: event) }
  let(:sender) { described_class.new(reminder) }

  ['America/Guayaquil', 'America/New_York', 'Europe/Madrid'].each do |zone_name|
    context "with #{zone_name}" do
      let(:timezone) { zone_name }

      it 'uses one civil day and clock for Captain, invitation and reminder variables' do
        expected = event.start_at.in_time_zone(timezone)
        values = Integrations::GoogleCalendar::InvitationText.values_for(account: account, start_at: event.start_at, timezone: timezone)
        expect(tool.send(:format_time, event.start_at)).to eq(sender.send(:appointment_drop).fetch('datetime'))
        expect(values.fetch('hora')).to eq(sender.send(:appointment_drop).fetch('time'))
        expect(sender.send(:appointment_drop).fetch('time')).to eq(expected.strftime('%H:%M'))
        expect(sender.send(:appointment_drop).fetch('date')).to include(expected.day.to_s)
      end
    end
  end

  context 'with a DST fold' do
    let(:timezone) { 'America/New_York' }

    it 'shares the earlier-local and explicit-offset parsing contract' do
      expect(tool.send(:parse_time, '2030-11-03T01:30:00').utc.iso8601).to eq('2030-11-03T05:30:00Z')
      expect(tool.send(:parse_time, '2030-11-03T01:30:00-05:00').utc.iso8601).to eq('2030-11-03T06:30:00Z')
      expect(tool.send(:parse_time, '2030-03-10T02:30:00')).to be_nil
    end
  end
end
