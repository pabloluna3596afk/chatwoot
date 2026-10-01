require 'rails_helper'

RSpec.describe Captain::Assistant, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh')
  end
  let!(:calendar) { connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true) }

  def appointments(overrides = {})
    { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' }.merge(overrides)
  end

  def assign(settings)
    assistant.config = assistant.config.merge('appointments' => settings)
  end

  describe 'appointments settings' do
    it 'is disabled with defaults when nothing is configured' do
      expect(assistant.appointments).not_to be_enabled
      expect(assistant.appointments.slot_duration_minutes).to eq(30)
    end

    it 'accepts a valid enabled configuration and normalizes it' do
      assign(appointments('slot_duration_minutes' => '45'))

      expect(assistant).to be_valid
      expect(assistant.config['appointments']).to include('enabled' => true, 'slot_duration_minutes' => 45, 'min_notice_minutes' => 60)
    end

    it 'accepts a disabled configuration with no calendar' do
      assign('enabled' => false)

      expect(assistant).to be_valid
    end

    it 'rejects a configuration that is not an object' do
      assign('yes')

      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to include('appointments must be an object')
    end

    it 'requires a calendar connection of this account when enabled' do
      assign(appointments('calendar_connection_id' => nil))
      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to include('appointments calendar_connection_id is invalid')

      other = CalendarConnection.create!(account: create(:account), provider: 'google', email: 'other@example.com', refresh_token: 'r')
      assign(appointments('calendar_connection_id' => other.id))
      expect(assistant).not_to be_valid
    end

    it 'rejects an inactive connection' do
      connection.update!(is_active: false)
      assign(appointments)

      expect(assistant).not_to be_valid
    end

    it 'requires an enabled calendar of that connection' do
      assign(appointments('calendar_id' => 'missing'))
      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to include('appointments calendar_id must be an enabled calendar of the connection')

      calendar.update!(is_enabled: false)
      assign(appointments)
      expect(assistant).not_to be_valid
    end

    it 'rejects out of range numbers' do
      { 'slot_duration_minutes' => 4, 'min_notice_minutes' => -1, 'booking_window_days' => 0 }.each do |key, value|
        assign(appointments(key => value))
        expect(assistant).not_to be_valid, "expected #{key}=#{value} to be invalid"
      end
      assign(appointments('slot_duration_minutes' => 'soon'))
      expect(assistant).not_to be_valid
    end

    it 'accepts the numbers at the edges of their ranges' do
      assign(appointments('slot_duration_minutes' => 240, 'min_notice_minutes' => 0, 'booking_window_days' => 90))

      expect(assistant).to be_valid
    end

    it 'rejects unknown contact fields and accepts a subset' do
      assign(appointments('required_contact_fields' => %w[name address]))
      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to include('appointments required_contact_fields must be a subset of name, phone, email')

      assign(appointments('required_contact_fields' => %w[phone]))
      expect(assistant).to be_valid
    end

    it 'does not re-validate the calendar on unrelated saves' do
      assign(appointments)
      assistant.save!
      calendar.update!(is_enabled: false)
      assistant.reload

      assistant.name = 'Renamed'
      expect(assistant).to be_valid
    end

    it 'validates the calendar again when the appointments settings change' do
      assign(appointments)
      assistant.save!
      calendar.update!(is_enabled: false)
      assistant.reload

      assign(appointments('slot_duration_minutes' => 60))
      expect(assistant).not_to be_valid
    end
  end
end
