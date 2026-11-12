require 'rails_helper'

RSpec.describe Whatsapp::TemplateEditValidator do
  let(:components) do
    [
      { type: 'HEADER', format: 'TEXT', text: 'Pedido' },
      { type: 'BODY', text: 'Hola {{1}}.', example: { body_text: [['Ana']] } },
      { type: 'FOOTER', text: 'Gracias' },
      { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'Sí' }, { type: 'QUICK_REPLY', text: 'No' }] }
    ]
  end
  let(:original) { { name: 'test', category: 'UTILITY', status: 'APPROVED', components: components } }
  let(:validator) { described_class.new(original) }

  it 'compares string and symbol keys independent of insertion order and trims example whitespace' do
    changed = components.map { |item| item.stringify_keys.to_a.reverse.to_h }
    changed[1]['example'] = { 'body_text' => [[' Ana ']] }

    expect(validator.unchanged?(changed, category: 'UTILITY')).to be(true)
  end

  [0, 1, 2].each do |index|
    it "detects exact text changes in component #{index}, including whitespace" do
      changed = components.deep_dup
      changed[index][:text] += ' '

      expect(validator.unchanged?(changed)).to be(false)
    end
  end

  it 'detects changed samples' do
    changed = components.deep_dup
    changed[1][:example][:body_text] = [['Luis']]

    expect(validator.unchanged?(changed)).to be(false)
  end

  it 'detects changed button labels and order' do
    changed = components.deep_dup
    changed.last[:buttons].first[:text] = 'Confirmar'
    expect(validator.unchanged?(changed)).to be(false)

    changed.last[:buttons] = components.last[:buttons].reverse
    expect(validator.unchanged?(changed)).to be(false)
  end

  it 'still validates identity when the components did not change' do
    expect { validator.validate!(components, name: 'otro') }.to raise_error do |error|
      expect(error.code).to eq('edit_identity_locked')
    end
  end
end
