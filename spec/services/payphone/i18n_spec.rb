require 'rails_helper'

RSpec.describe I18n do
  it 'keeps English and Spanish configuration keys in parity' do
    english = described_class.t('super_admin.payphone', locale: :en).deep_stringify_keys
    spanish = described_class.t('super_admin.payphone', locale: :es).deep_stringify_keys
    key_tree = lambda do |translations|
      translations.transform_values do |value|
        value.is_a?(Hash) ? key_tree.call(value) : nil
      end
    end

    expect(key_tree.call(spanish)).to eq(key_tree.call(english))
  end
end
