require 'rails_helper'

RSpec.describe Variables::ValueNormalizer do
  let(:normalizer) { described_class.new(drops: { 'contact' => { 'name' => 'Ana' }, 'date' => DateDrop.new(timezone: 'America/Guayaquil') }) }

  it 'MV-11: renders every multi_list item before returning' do
    definition = build(:custom_attribute_definition, attribute_display_type: 'multi_list')
    expect(normalizer.normalize(definition, ['{{ contact.name }}', 'literal', '{% if contact.name %}VIP{% endif %}']))
      .to eq(%w[Ana literal VIP])
  end

  it 'retains typed numbers, false, and date normalization' do
    expect(normalizer.normalize(build(:custom_attribute_definition, attribute_display_type: 'number'), '0')).to eq(0)
    expect(normalizer.normalize(build(:custom_attribute_definition, attribute_display_type: 'checkbox'), false)).to be(false)
    expect(normalizer.normalize(build(:custom_attribute_definition, attribute_display_type: 'date'), '20/10/2026')).to eq('2026-10-20')
  end
end
