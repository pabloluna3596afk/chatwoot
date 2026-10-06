require 'rails_helper'

RSpec.describe Whatsapp::Flows::FlowJsonValidator do
  def footer(action)
    { 'type' => 'Footer', 'label' => 'Continuar', 'on-click-action' => action }
  end

  def screen(id, children, **extra)
    form = { 'type' => 'Form', 'name' => 'form', 'children' => children }
    { 'id' => id, 'title' => id, 'layout' => { 'type' => 'SingleColumnLayout', 'children' => [form] }, 'data' => {} }
      .merge(extra.transform_keys(&:to_s))
  end

  def navigate(target, payload = {})
    { 'name' => 'navigate', 'next' => { 'type' => 'screen', 'name' => target }, 'payload' => payload }
  end

  def complete_screen(id = 'FIN', **extra)
    screen(id, [footer({ 'name' => 'complete', 'payload' => {} })], 'terminal' => true, 'success' => true, **extra)
  end

  def flow(*screens)
    { 'version' => '7.3', 'screens' => screens }
  end

  def codes(value)
    described_class.new(value).call.errors.pluck(:code)
  end

  it 'accepts a flow that navigates to a terminal screen that completes' do
    expect(described_class.new(flow(screen('INICIO', [footer(navigate('FIN'))]), complete_screen)).call).to be_valid
  end

  it 'needs screens and a version' do
    expect(codes({})).to eq(['no_screens'])
    expect(codes({ 'screens' => [complete_screen] })).to eq(['invalid_version'])
  end

  it 'refuses repeated, reserved or badly written screen ids' do
    expect(codes(flow(complete_screen('A'), complete_screen('A')))).to include('screen_id_duplicate')
    expect(codes(flow(complete_screen('SUCCESS')))).to include('screen_id_reserved')
    expect(codes(flow(complete_screen('P1')))).to include('screen_id_invalid')
  end

  it 'needs a terminal screen with success, and the terminal one has to complete' do
    expect(codes(flow(screen('A', [footer({ 'name' => 'complete', 'payload' => {} })])))).to include('no_terminal_screen')
    expect(codes(flow(screen('A', [footer({ 'name' => 'complete', 'payload' => {} })], 'terminal' => true)))).to include('no_success_screen')
    expect(codes(flow(screen('A', [footer(navigate('A'))], 'terminal' => true, 'success' => true)))).to include('terminal_must_complete')
  end

  it 'asks for exactly one footer per screen, without emoji, that navigates unless the screen is terminal' do
    expect(codes(flow(screen('A', []), complete_screen))).to include('footer_missing')
    two = screen('A', [footer(navigate('FIN')), footer(navigate('FIN'))])
    expect(codes(flow(two, complete_screen))).to include('footer_multiple')
    emoji = screen('A', [{ 'type' => 'Footer', 'label' => 'Enviar 😀', 'on-click-action' => navigate('FIN') }])
    expect(codes(flow(emoji, complete_screen))).to include('footer_emoji')
    expect(codes(flow(screen('A', [footer({ 'name' => 'complete', 'payload' => {} })]), complete_screen))).to include('screen_must_navigate')
  end

  it 'checks that a navigate points to a screen and covers the data that screen declares' do
    expect(codes(flow(screen('A', [footer(navigate('NADA'))]), complete_screen))).to include('navigate_unknown_screen')

    target = complete_screen('FIN', 'data' => { 'nombre' => { 'type' => 'string', '__example__' => '' } })
    result = described_class.new(flow(screen('A', [footer(navigate('FIN'))]), target)).call
    expect(result.errors).to include(a_hash_including(code: 'missing_payload_data', details: { target: 'FIN', keys: ['nombre'] }))
  end

  it 'checks every reference: ${form.x} to a field of the screen, ${data.x} to a declared one, names not repeated, examples present' do
    input = { 'type' => 'TextInput', 'name' => 'nombre', 'label' => 'Nombre' }
    broken = screen('A', [input, input, footer(navigate('FIN', 'otro' => '${form.otro}', 'viejo' => '${data.viejo}'))],
                    'data' => { 'sin_ejemplo' => { 'type' => 'string' } })

    result = codes(flow(broken, complete_screen))

    expect(result).to include('duplicate_field_name', 'unknown_form_reference', 'undeclared_data_reference', 'data_without_example')
  end

  it 'warns about screens nobody reaches and about loops' do
    expect(codes(flow(screen('A', [footer(navigate('FIN'))]), complete_screen, complete_screen('HUERFANA')))).to include('unreachable_screen')

    loop_flow = flow(screen('A', [footer(navigate('B'))]), screen('B', [footer(navigate('A'))]), complete_screen)
    expect(codes(loop_flow)).to include('screens_loop')
  end

  it 'limits the components of a screen' do
    many = Array.new(50) { |index| { 'type' => 'TextBody', 'text' => "t#{index}" } }

    expect(codes(flow(screen('A', many + [footer(navigate('FIN'))]), complete_screen))).to include('too_many_components')
  end

  it 'looks inside Ifs and Switches' do
    conditional = { 'type' => 'If', 'condition' => '${form.x} == 1', 'then' => [{ 'type' => 'TextInput', 'name' => 'x', 'label' => 'X' }] }
    switch = { 'type' => 'Switch', 'value' => '${form.x}', 'cases' => { 'a' => [{ 'type' => 'TextInput', 'name' => 'x', 'label' => 'Otra X' }] } }

    expect(codes(flow(screen('A', [conditional, switch, footer(navigate('FIN'))]), complete_screen))).to include('duplicate_field_name')
  end
end
