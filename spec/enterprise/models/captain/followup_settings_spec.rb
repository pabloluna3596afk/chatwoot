require 'rails_helper'

RSpec.describe Captain::FollowupSettings do
  describe '.normalize' do
    it 'returns the defaults: inactivity on, one nudge after 30 minutes, close after 120, re-engagement off' do
      expect(described_class.normalize(nil)).to eq(
        'inactivity_enabled' => true, 'inactivity_after_minutes' => 30, 'max_nudges' => 1, 'close_after_minutes' => 120,
        'reengagement_enabled' => false, 'reengagement_template' => nil
      )
    end

    it 'casts strings, drops unknown keys and keeps only name and language of a template' do
      result = described_class.normalize(
        'inactivity_enabled' => 'false', 'inactivity_after_minutes' => '45', 'max_nudges' => '2', 'close_after_minutes' => 60,
        'reengagement_enabled' => 'true', 'reengagement_template' => { 'name' => 'volver', 'language' => 'es', 'extra' => 'x' }, 'other' => 1
      )

      expect(result).to eq(
        'inactivity_enabled' => false, 'inactivity_after_minutes' => 45, 'max_nudges' => 2, 'close_after_minutes' => 60,
        'reengagement_enabled' => true, 'reengagement_template' => { 'name' => 'volver', 'language' => 'es' }
      )
    end

    it 'reads "no" as off, not as true' do
      expect(described_class.normalize('inactivity_enabled' => 'no')['inactivity_enabled']).to be(false)
    end

    it 'keeps values that are not numbers so the validator can reject them' do
      expect(described_class.normalize('max_nudges' => 'many')['max_nudges']).to eq('many')
    end
  end
end
