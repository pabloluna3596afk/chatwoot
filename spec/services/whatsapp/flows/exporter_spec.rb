require 'rails_helper'

RSpec.describe Whatsapp::Flows::Exporter do
  let(:definition) do
    {
      'schema_version' => 1,
      'screens' => [
        { 'title' => 'Tus datos', 'button' => 'Continuar',
          'blocks' => [
            { 'type' => 'heading', 'text' => 'Hola' },
            { 'type' => 'short_text', 'key' => 'nombre', 'label' => 'Nombre', 'required' => true, 'input' => 'text',
              'helper' => 'Como en tu cédula' },
            { 'type' => 'dropdown', 'key' => 'tipo', 'label' => 'Tipo',
              'options' => [{ 'id' => 'a', 'title' => 'A' }, { 'id' => 'otro', 'title' => 'Otro' }] },
            { 'type' => 'short_text', 'key' => 'cual', 'label' => '¿Cuál?',
              'visible_when' => { 'key' => 'tipo', 'op' => 'equals', 'value' => 'otro' } }
          ] },
        { 'title' => 'Detalles', 'button' => 'Continuar',
          'blocks' => [
            { 'type' => 'checkbox', 'key' => 'temas', 'label' => 'Temas', 'min' => 1, 'options' => [{ 'id' => 'x', 'title' => 'X' }] },
            { 'type' => 'optin', 'key' => 'acepto', 'label' => 'Acepto' },
            { 'type' => 'long_text', 'key' => 'nota', 'label' => 'Nota', 'visible_when' => { 'key' => 'tipo', 'op' => 'not_equals', 'value' => 'a' } }
          ] },
        { 'title' => 'Adjuntos', 'button' => 'Enviar',
          'blocks' => [
            { 'type' => 'photo', 'key' => 'foto', 'label' => 'Foto', 'required' => true, 'max_files' => 2 },
            { 'type' => 'document', 'key' => 'pdf', 'label' => 'Documento', 'helper' => 'PDF o Word' },
            { 'type' => 'text', 'text' => 'Gracias', 'visible_when' => { 'key' => 'acepto', 'op' => 'equals', 'value' => 'true' } }
          ] }
      ]
    }
  end
  let(:flow) { described_class.new(definition).call }

  def screen(index)
    flow['screens'][index]
  end

  def form(index)
    screen(index).dig('layout', 'children', 0)
  end

  def footer(index)
    form(index)['children'].last
  end

  it 'exports Flow JSON 7.3 with one screen per screen of the form, chained in order, letters and underscore only' do
    expect(flow['version']).to eq('7.3')
    expect(flow['screens'].pluck('id')).to eq(%w[PANTALLA_A PANTALLA_B PANTALLA_C])
    expect(flow['screens'].pluck('title')).to eq(['Tus datos', 'Detalles', 'Adjuntos'])
    expect(flow['screens'].all? { |item| item.dig('layout', 'type') == 'SingleColumnLayout' }).to be true
    expect(form(0)).to include('type' => 'Form', 'name' => 'form')
  end

  it 'makes only the last screen terminal and successful' do
    expect(screen(0).keys).not_to include('terminal')
    expect(screen(1).keys).not_to include('terminal')
    expect(screen(2)).to include('terminal' => true, 'success' => true)
  end

  it 'navigates to the next screen carrying every answer so far, and completes with all of them' do
    expect(footer(0)['on-click-action']).to eq(
      'name' => 'navigate', 'next' => { 'type' => 'screen', 'name' => 'PANTALLA_B' },
      'payload' => { 'nombre' => '${form.nombre}', 'tipo' => '${form.tipo}', 'cual' => '${form.cual}' }
    )
    expect(footer(1)['on-click-action']['payload']).to eq(
      'nombre' => '${data.nombre}', 'tipo' => '${data.tipo}', 'cual' => '${data.cual}',
      'temas' => '${form.temas}', 'acepto' => '${form.acepto}', 'nota' => '${form.nota}'
    )
    expect(footer(2)['on-click-action']['name']).to eq('complete')
    expect(footer(2)['on-click-action']['payload'].keys).to eq(%w[nombre tipo cual temas acepto nota foto pdf])
    expect(footer(2)['on-click-action']['payload']).to include('nombre' => '${data.nombre}', 'foto' => '${form.foto}', 'pdf' => '${form.pdf}')
  end

  it 'declares in each screen the data coming from the earlier ones, with an example and the right type' do
    expect(screen(0)['data']).to eq({})
    expect(screen(1)['data'].keys).to eq(%w[nombre tipo cual])
    expect(screen(2)['data']['temas']).to eq('type' => 'array', 'items' => { 'type' => 'string' }, '__example__' => [])
    expect(screen(2)['data']['acepto']).to eq('type' => 'boolean', '__example__' => false)
    expect(screen(2)['data']['nombre']).to eq('type' => 'string', '__example__' => '')
    expect(screen(2)['data'].keys).to eq(%w[nombre tipo cual temas acepto nota])
  end

  it 'builds the components of every kind of block' do
    children = form(0)['children']

    expect(children[0]).to eq('type' => 'TextHeading', 'text' => 'Hola')
    expect(children[1]).to eq('type' => 'TextInput', 'name' => 'nombre', 'label' => 'Nombre', 'required' => true, 'input-type' => 'text',
                              'helper-text' => 'Como en tu cédula')
    expect(children[2]).to include('type' => 'Dropdown', 'name' => 'tipo', 'required' => false,
                                   'data-source' => [{ 'id' => 'a', 'title' => 'A' }, { 'id' => 'otro', 'title' => 'Otro' }])
    checkbox = form(1)['children'][0]
    expect(checkbox).to include('type' => 'CheckboxGroup', 'name' => 'temas', 'min-selected-items' => 1)
    expect(form(1)['children'][1]).to include('type' => 'OptIn', 'name' => 'acepto')
    expect(form(1)['children'][2]).to include('type' => 'If', 'then' => [include('type' => 'TextArea', 'name' => 'nota')])
  end

  it 'builds the file pickers' do
    photo, document = form(2)['children']

    expect(photo).to include('type' => 'PhotoPicker', 'name' => 'foto', 'photo-source' => 'camera_gallery', 'min-uploaded-photos' => 1,
                             'max-uploaded-photos' => 2)
    expect(document).to include('type' => 'DocumentPicker', 'name' => 'pdf', 'description' => 'PDF o Word', 'min-uploaded-documents' => 0,
                                'max-uploaded-documents' => 1)
    expect(document['allowed-mime-types']).to include('application/pdf')
  end

  it 'wraps a conditional block in an If on the answer: the form for this screen, the data for an earlier one' do
    same = form(0)['children'][3]
    earlier = form(1)['children'][2]
    optin = form(2)['children'][2]

    expect(same).to include('type' => 'If', 'condition' => "${form.tipo} == 'otro'")
    expect(same['then'].first).to include('type' => 'TextInput', 'name' => 'cual')
    expect(earlier['condition']).to eq("${data.tipo} != 'a'")
    expect(optin['condition']).to eq('${data.acepto} == true')
  end

  it 'produces Flow JSON that passes the structural validation' do
    result = Whatsapp::Flows::FlowJsonValidator.new(flow).call

    expect(result.errors).to eq([])
  end

  it 'reads a definition with symbol keys and exports a single screen as the terminal one' do
    single = { screens: [{ title: 'Uno', button: 'Enviar', blocks: [{ type: 'text', text: 'Hola' }] }] }
    json = described_class.new(single).call

    expect(json['screens'].size).to eq(1)
    expect(json['screens'][0]).to include('id' => 'PANTALLA_A', 'terminal' => true, 'success' => true)
    expect(json['screens'][0].dig('layout', 'children', 0, 'children').last['on-click-action']).to eq('name' => 'complete', 'payload' => {})
    expect(Whatsapp::Flows::FlowJsonValidator.new(json).call.errors).to eq([])
  end

  it 'names screens past Z with letters only' do
    expect((0..27).map do |index|
      Whatsapp::Flows::Spec.screen_id(index)
    end.values_at(0, 25, 26, 27)).to eq(%w[PANTALLA_A PANTALLA_Z PANTALLA_AA PANTALLA_AB])
  end
end
