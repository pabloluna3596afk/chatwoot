require 'rails_helper'

RSpec.describe Captain::AppointmentsSettings do
  let(:reminder_defaults) do
    { 'reminder_1' => { 'enabled' => true, 'hours_before' => 24 }, 'reminder_2' => { 'enabled' => true, 'hours_before' => 3 },
      'template_reminder' => nil, 'template_cancelled' => nil }
  end

  describe '.normalize' do
    it 'returns the defaults for a blank value' do
      expect(described_class.normalize(nil)).to include(
        'enabled' => false, 'calendar_connection_id' => nil, 'calendar_id' => nil, 'slot_duration_minutes' => 30,
        'required_contact_fields' => %w[name phone email], 'min_notice_minutes' => 60, 'booking_window_days' => 14
      ).and include(reminder_defaults)
    end

    it 'casts strings, drops unknown keys and keeps provided values' do
      result = described_class.normalize(
        'enabled' => 'true', 'calendar_connection_id' => '7', 'calendar_id' => 'cal-1', 'slot_duration_minutes' => '45',
        'required_contact_fields' => %w[phone phone], 'min_notice_minutes' => 120, 'booking_window_days' => '30', 'other' => 'x'
      )

      expect(result).to include(
        'enabled' => true, 'calendar_connection_id' => 7, 'calendar_id' => 'cal-1', 'slot_duration_minutes' => 45,
        'required_contact_fields' => %w[phone], 'min_notice_minutes' => 120, 'booking_window_days' => 30
      ).and include(reminder_defaults)
    end

    it 'has no send_confirmation setting: the confirmation is always the booking reply' do
      expect(described_class.normalize('send_confirmation' => false)).not_to have_key('send_confirmation')
    end

    it 'casts the reminders strictly: the switch ("no" is off) and the hours' do
      result = described_class.normalize(
        'reminder_1' => { 'enabled' => 'no', 'hours_before' => '48' }, 'reminder_2' => { 'enabled' => 'true', 'hours_before' => '' }
      )

      expect(result).to include('reminder_1' => { 'enabled' => false, 'hours_before' => 48 },
                                'reminder_2' => { 'enabled' => true, 'hours_before' => 3 })
    end

    it 'keeps hours that are not numbers so the validator can reject them' do
      expect(described_class.normalize('reminder_1' => { 'hours_before' => 'soon' })['reminder_1']['hours_before']).to eq('soon')
    end

    it 'reads the old 24 h / 2 h switches as the two reminders, with their old lead times' do
      result = described_class.normalize('reminder_24h' => true, 'reminder_2h' => false)

      expect(result).to include('reminder_1' => { 'enabled' => true, 'hours_before' => 24 },
                                'reminder_2' => { 'enabled' => false, 'hours_before' => 2 })
    end

    it 'prefers the new reminder over the old switch' do
      result = described_class.normalize('reminder_1' => { 'enabled' => true, 'hours_before' => 12 }, 'reminder_24h' => false)

      expect(result['reminder_1']).to eq('enabled' => true, 'hours_before' => 12)
    end

    it 'has no confirmation template: the confirmation is always the booking reply, free inside the 24 h window' do
      result = described_class.normalize('template_confirmation' => { 'name' => 'confirmacion', 'language' => 'es' })

      expect(result).not_to have_key('template_confirmation')
    end

    it 'keeps the name, the language and the texts of the variables of a template, and nothing else' do
      result = described_class.normalize(
        'template_reminder' => { 'name' => 'recordatorio', 'language' => 'es', 'extra' => 'x',
                                 'processed_params' => { 'body' => { '1' => '{{ contact.name }}', 'nombre' => 'Consulta' },
                                                         'header' => { 'titulo' => '{{ appointment.title }}' }, 'footer' => { 'x' => 'y' } } },
        'template_cancelled' => nil
      )

      expect(result).to include(
        'template_reminder' => { 'name' => 'recordatorio', 'language' => 'es',
                                 'processed_params' => { 'body' => { '1' => '{{ contact.name }}', 'nombre' => 'Consulta' },
                                                         'header' => { 'titulo' => '{{ appointment.title }}' } } },
        'template_cancelled' => nil
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
