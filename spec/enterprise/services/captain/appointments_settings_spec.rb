require 'rails_helper'

RSpec.describe Captain::AppointmentsSettings do
  describe '.normalize' do
    it 'returns the defaults for a blank value' do
      expect(described_class.normalize(nil)).to eq(
        'enabled' => false, 'calendar_connection_id' => nil, 'calendar_id' => nil, 'slot_duration_minutes' => 30,
        'required_contact_fields' => %w[name phone email], 'min_notice_minutes' => 60, 'booking_window_days' => 14
      )
    end

    it 'casts strings, drops unknown keys and keeps provided values' do
      result = described_class.normalize(
        'enabled' => 'true', 'calendar_connection_id' => '7', 'calendar_id' => 'cal-1', 'slot_duration_minutes' => '45',
        'required_contact_fields' => %w[phone phone], 'min_notice_minutes' => 120, 'booking_window_days' => '30', 'other' => 'x'
      )

      expect(result).to eq(
        'enabled' => true, 'calendar_connection_id' => 7, 'calendar_id' => 'cal-1', 'slot_duration_minutes' => 45,
        'required_contact_fields' => %w[phone], 'min_notice_minutes' => 120, 'booking_window_days' => 30
      )
    end

    it 'accepts symbol keys and blank numbers fall back to the default' do
      result = described_class.normalize(enabled: false, slot_duration_minutes: '', calendar_connection_id: '')

      expect(result).to include('enabled' => false, 'slot_duration_minutes' => 30, 'calendar_connection_id' => nil)
    end

    it 'keeps values that are not numbers so the validator can reject them' do
      expect(described_class.normalize('slot_duration_minutes' => 'soon')['slot_duration_minutes']).to eq('soon')
    end

    it 'does not share the default fields array between calls' do
      described_class.normalize(nil)['required_contact_fields'] << 'extra'

      expect(described_class.normalize(nil)['required_contact_fields']).to eq(%w[name phone email])
    end
  end

  describe 'accessors' do
    it 'reads the normalized values' do
      settings = described_class.new('enabled' => true, 'calendar_id' => 'cal-1')

      expect(settings).to be_enabled
      expect(settings).to have_attributes(calendar_id: 'cal-1', slot_duration_minutes: 30, min_notice_minutes: 60, booking_window_days: 14)
      expect(settings.required_contact_fields).to eq(%w[name phone email])
    end

    it 'is disabled by default' do
      expect(described_class.new).not_to be_enabled
    end
  end
end
