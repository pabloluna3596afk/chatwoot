require 'rails_helper'

RSpec.describe I18n do
  it 'keeps English and Spanish configuration keys in parity' do
    english = described_class.t('super_admin.payphone', locale: :en).deep_stringify_keys
    spanish = described_class.t('super_admin.payphone', locale: :es).deep_stringify_keys

    expect(spanish.keys).to match_array(english.keys)
    english.each do |section, entries|
      expect(spanish.fetch(section).keys).to match_array(entries.keys)
    end
  end
end
