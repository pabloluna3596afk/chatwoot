require 'rails_helper'

RSpec.describe Whatsapp::Flows::DefinitionValidator do
  def definition(screens)
    { 'schema_version' => 1, 'screens' => screens }
  end

  def screen(blocks, title: 'Tus datos', button: 'Continuar')
    { 'title' => title, 'button' => button, 'blocks' => blocks }
  end

  def text_input(key, **extra)
    { 'type' => 'short_text', 'key' => key, 'label' => 'Nombre' }.merge(extra.transform_keys(&:to_s))
  end

  def dropdown(key = 'tipo', options: [{ 'id' => 'a', 'title' => 'A' }, { 'id' => 'b', 'title' => 'B' }])
    { 'type' => 'dropdown', 'key' => key, 'label' => 'Tipo', 'options' => options }
  end

  def codes(value)
    described_class.new(value).call.errors.pluck(:code)
  end

  it 'accepts a form with several screens, every kind of block and a condition' do
    value = definition(
      [
        screen([{ 'type' => 'heading', 'text' => 'Hola' }, { 'type' => 'text', 'text' => 'Cuéntanos' }, text_input('nombre', 'required' => true),
                dropdown, { 'type' => 'radio', 'key' => 'turno', 'label' => 'Turno', 'options' => [{ 'id' => 'am', 'title' => 'Mañana' }] }]),
        screen(
          [{ 'type' => 'checkbox', 'key' => 'temas', 'label' => 'Temas', 'min' => 1, 'max' => 2, 'options' => [{ 'id' => 'x', 'title' => 'X' },
                                                                                                               { 'id' => 'y', 'title' => 'Y' }] },
           { 'type' => 'date', 'key' => 'fecha', 'label' => 'Fecha' }, { 'type' => 'optin', 'key' => 'acepto', 'label' => 'Acepto' },
           { 'type' => 'photo', 'key' => 'foto', 'label' => 'Foto', 'max_files' => 2 }, { 'type' => 'document', 'key' => 'pdf', 'label' => 'PDF' },
           text_input('detalle', 'visible_when' => { 'key' => 'tipo', 'op' => 'equals', 'value' => 'a' })],
          title: 'Más', button: 'Enviar'
        )
      ]
    )

    result = described_class.new(value).call

    expect(result.errors).to be_empty
    expect(result).to be_valid
  end

  it 'needs screens, each with a title, a button and blocks' do
    expect(codes({})).to eq(['screens_required'])
    expect(codes(definition([]))).to eq(['screens_required'])
    expect(codes(definition([{ 'blocks' => [] }]))).to contain_exactly('screen_title_required', 'button_required', 'blocks_required')
  end

  it 'keeps to the limits of Meta: titles, labels, texts, buttons without emoji, options' do
    long = 'a' * 100
    value = definition(
      [screen([{ 'type' => 'heading', 'text' => long }, text_input('nombre', 'label' => 'a' * 21, 'helper' => long),
               dropdown('tipo', options: [{ 'id' => 'a', 'title' => 'a' * 31 }])], title: 'a' * 31, button: 'Enviar 😀')]
    )

    expect(codes(value)).to contain_exactly('screen_title_too_long', 'button_no_emoji', 'text_too_long', 'label_too_long', 'helper_too_long',
                                            'option_title_too_long')
  end

  it 'checks the options: present, valid ids, no repeats, not too many' do
    expect(codes(definition([screen([dropdown('tipo', options: [])])]))).to eq(['options_required'])
    expect(codes(definition([screen([dropdown('tipo', options: [{ 'id' => 'A B', 'title' => 'A' }])])]))).to eq(['option_id_invalid'])
    repeated = [{ 'id' => 'a', 'title' => 'A' }, { 'id' => 'a', 'title' => 'B' }]
    expect(codes(definition([screen([dropdown('tipo', options: repeated)])]))).to eq(['option_ids_duplicate'])
    many = Array.new(21) { |index| { 'id' => "o#{index}", 'title' => 'O' } }
    radio = { 'type' => 'radio', 'key' => 'r', 'label' => 'R', 'options' => many }
    expect(codes(definition([screen([radio])]))).to eq(['too_many_options'])
  end

  it 'needs a unique, well formed key for every answer' do
    value = definition([screen([text_input('Nombre'), text_input('correo'), text_input('correo')])])

    expect(codes(value)).to contain_exactly('key_invalid', 'key_duplicate')
  end

  it 'limits the components of a screen, the opt-ins and the file pickers' do
    blocks = Array.new(50) { |index| { 'type' => 'text', 'text' => "t#{index}" } }
    expect(codes(definition([screen(blocks)]))).to eq(['too_many_components'])

    optins = Array.new(6) { |index| { 'type' => 'optin', 'key' => "o#{index}", 'label' => 'Acepto' } }
    expect(codes(definition([screen(optins)]))).to eq(['too_many_optins'])

    photos = Array.new(2) { |index| { 'type' => 'photo', 'key' => "f#{index}", 'label' => 'Foto' } }
    expect(codes(definition([screen(photos)]))).to eq(['too_many_file_blocks'])
  end

  it 'checks the selection range of a checkbox and the number of files' do
    checkbox = { 'type' => 'checkbox', 'key' => 'c', 'label' => 'C', 'min' => 3, 'max' => 1, 'options' => [{ 'id' => 'a', 'title' => 'A' }] }
    expect(codes(definition([screen([checkbox])]))).to eq(['selection_range_invalid'])

    photo = { 'type' => 'photo', 'key' => 'f', 'label' => 'Foto', 'max_files' => 31 }
    expect(codes(definition([screen([photo])]))).to eq(['files_range_invalid'])
  end

  describe 'conditions' do
    def with_condition(condition, screens_before: [])
      definition(screens_before + [screen([dropdown, text_input('detalle', 'visible_when' => condition)])])
    end

    it 'accepts equals and not_equals on an earlier answer, on this screen or before' do
      earlier = [screen([dropdown('modo')])]
      value = definition(earlier + [screen([text_input('detalle', 'visible_when' => { 'key' => 'modo', 'op' => 'not_equals', 'value' => 'a' })])])

      expect(codes(value)).to be_empty
      expect(codes(with_condition({ 'key' => 'tipo', 'op' => 'equals', 'value' => 'b' }))).to be_empty
    end

    it 'refuses an unknown answer, one that is not earlier, one that is not a single value and a value it cannot have' do
      expect(codes(with_condition({ 'key' => 'nada', 'op' => 'equals', 'value' => 'a' }))).to eq(['condition_unknown_field'])
      expect(codes(with_condition({ 'key' => 'detalle', 'op' => 'equals', 'value' => 'a' }))).to eq(['condition_not_earlier'])
      expect(codes(with_condition({ 'key' => 'tipo', 'op' => 'equals', 'value' => 'z' }))).to eq(['condition_value_invalid'])
      expect(codes(with_condition({ 'key' => 'tipo', 'op' => 'maybe', 'value' => 'a' }))).to eq(['condition_invalid'])

      date = { 'type' => 'date', 'key' => 'fecha', 'label' => 'Fecha' }
      value = definition([screen([date, text_input('detalle', 'visible_when' => { 'key' => 'fecha', 'op' => 'equals', 'value' => 'x' })])])
      expect(codes(value)).to eq(['condition_field_unsupported'])
    end

    it 'takes true or false for an opt-in and a plain text for a text answer' do
      optin = { 'type' => 'optin', 'key' => 'acepto', 'label' => 'Acepto' }
      ok = definition([screen([optin, text_input('a', 'visible_when' => { 'key' => 'acepto', 'op' => 'equals', 'value' => 'true' })])])
      bad = definition([screen([optin, text_input('a', 'visible_when' => { 'key' => 'acepto', 'op' => 'equals', 'value' => 'si' })])])
      quote = definition([screen([text_input('n'), text_input('a', 'visible_when' => { 'key' => 'n', 'op' => 'equals', 'value' => "o'x" })])])

      expect(codes(ok)).to be_empty
      expect(codes(bad)).to eq(['condition_value_invalid'])
      expect(codes(quote)).to eq(['condition_value_invalid'])
    end
  end

  it 'points to where the mistake is' do
    result = described_class.new(definition([screen([text_input('nombre', 'label' => 'a' * 25)])])).call

    expect(result.errors).to eq([{ code: 'label_too_long', path: 'screens.0.blocks.0.label', details: { limit: 20 } }])
  end

  it 'reads a definition with symbol keys too' do
    value = { screens: [{ title: 'T', button: 'B', blocks: [{ type: 'heading', text: 'Hola' }] }] }

    expect(described_class.new(value).call).to be_valid
  end
end
