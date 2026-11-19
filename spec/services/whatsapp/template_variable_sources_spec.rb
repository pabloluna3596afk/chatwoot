require 'rails_helper'

RSpec.describe Whatsapp::TemplateVariableSources do
  let(:channel) { create(:channel_whatsapp, validate_provider_config: false, sync_templates: false) }
  let(:service) { described_class.new(channel) }
  let(:template) do
    { 'name' => 'order', 'components' => [
      { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => '{{correo}}' },
      { 'type' => 'BODY', 'text' => '{{nombre}} {{pedido}} {{1}} {{fecha}} {{asistente}}' },
      { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{2}}' }] }
    ] }
  end

  it 'uses aliases, marks unknown and positional variables missing and excludes appointment aliases and buttons' do
    result = service.for(template)
    expect(result['header']).to eq('correo' => { source: 'alias', path: 'contact.email' })
    expect(result['body']['nombre']).to eq(source: 'alias', path: 'contact.name')
    expect(result['body']['asistente']).to eq(source: 'alias', path: 'assistant.name')
    %w[pedido 1 fecha].each { |name| expect(result['body'][name]).to eq(source: 'missing', path: nil) }
    expect(result['body']).not_to have_key('2')
  end

  it 'uses contact and conversation custom attribute aliases from the catalog' do
    create(:custom_attribute_definition, account: channel.account, attribute_model: 'contact_attribute', attribute_key: 'pedido')
    create(:custom_attribute_definition, account: channel.account, attribute_model: 'conversation_attribute', attribute_key: 'estado')
    template['components'].first['text'] = '{{conversacion_estado}}'
    result = service.for(template)
    expect(result['body']['pedido']).to eq(source: 'alias', path: "contact.custom_attribute['pedido']")
    expect(result['header']['conversacion_estado']).to eq(source: 'alias', path: "conversation.custom_attribute['estado']")
  end

  it 'prefers valid bindings over aliases and validates each binding against the message catalog' do
    channel.update!(template_variable_bindings: { 'order' => { 'nombre' => 'contact.first_name', 'pedido' => 'contact.unknown',
                                                               '1' => 'conversation.id', 'fecha' => 'appointment.date' } })
    result = service.for(template)
    expect(result['body']['nombre']).to eq(source: 'binding', path: 'contact.first_name')
    expect(result['body']['1']).to eq(source: 'binding', path: 'conversation.id')
    %w[pedido fecha].each { |name| expect(result['body'][name]).to eq(source: 'missing', path: nil) }
  end

  it 'does not treat media header text as variables' do
    template['components'].first['format'] = 'IMAGE'
    expect(service.for(template)['header']).to be_empty
  end
end
