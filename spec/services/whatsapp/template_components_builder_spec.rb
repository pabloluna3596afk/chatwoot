require 'rails_helper'

RSpec.describe Whatsapp::TemplateComponentsBuilder do
  def build(**parts)
    described_class.new(**{ body: { text: 'Hola' } }.merge(parts)).components
  end

  def error_code
    yield
    nil
  rescue described_class::Invalid => e
    e.code
  end

  describe '.valid_name?' do
    it 'accepts lowercase letters, digits and underscores only' do
      expect(described_class.valid_name?('recordatorio_cita_2')).to be true
      expect(described_class.valid_name?('Recordatorio')).to be false
      expect(described_class.valid_name?('con espacio')).to be false
      expect(described_class.valid_name?('')).to be false
    end
  end

  describe '#components' do
    it 'builds a body only template' do
      expect(build).to eq([{ type: 'BODY', text: 'Hola' }])
    end

    it 'adds the body examples when the body has variables' do
      components = build(body: { text: 'Hola {{1}}, tu cita es el {{2}}.', examples: %w[Ana lunes] })

      expect(components.first).to eq(type: 'BODY', text: 'Hola {{1}}, tu cita es el {{2}}.', example: { body_text: [%w[Ana lunes]] })
    end

    it 'builds a text header with its example, a footer and every kind of button' do
      components = build(
        header: { format: 'TEXT', text: 'Cita {{1}}', examples: ['lunes'] },
        footer: { text: 'Gracias' },
        buttons: [
          { type: 'QUICK_REPLY', text: 'Confirmar' },
          { type: 'URL', text: 'Ver', url: 'https://example.com/c/{{1}}', examples: ['https://example.com/c/9'] },
          { type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+593999999999' }
        ]
      )

      expect(components.map { |component| component[:type] }).to eq(%w[HEADER BODY FOOTER BUTTONS])
      expect(components[0]).to eq(type: 'HEADER', format: 'TEXT', text: 'Cita {{1}}', example: { header_text: ['lunes'] })
      expect(components[3][:buttons]).to eq(
        [
          { type: 'QUICK_REPLY', text: 'Confirmar' },
          { type: 'URL', text: 'Ver', url: 'https://example.com/c/{{1}}', example: ['https://example.com/c/9'] },
          { type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+593999999999' }
        ]
      )
    end

    it 'builds a media header from the example handle' do
      expect(build(header: { format: 'IMAGE', handle: '4::abc' }).first).to eq(
        type: 'HEADER', format: 'IMAGE', example: { header_handle: ['4::abc'] }
      )
    end
  end

  describe 'the rules Meta enforces' do
    it 'asks for a body, an example per variable and variables in order' do
      expect(error_code { build(body: { text: ' ' }) }).to eq('body_required')
      expect(error_code { build(body: { text: 'Hola {{1}} y {{2}}', examples: ['Ana'] }) }).to eq('example_required')
      expect(error_code { build(body: { text: 'Hola {{2}} adiós', examples: %w[a b] }) }).to eq('variables_not_sequential')
    end

    it 'does not let the body start or end with a variable' do
      expect(error_code { build(body: { text: '{{1}} hola', examples: ['Ana'] }) }).to eq('variable_at_edge')
      expect(error_code { build(body: { text: 'Hola {{1}}', examples: ['Ana'] }) }).to eq('variable_at_edge')
    end

    it 'limits the length of the body, header, footer and buttons' do
      expect(error_code { build(body: { text: 'a' * 1025 }) }).to eq('body_too_long')
      expect(error_code { build(header: { format: 'TEXT', text: 'a' * 61 }) }).to eq('header_text_too_long')
      expect(error_code { build(footer: { text: 'a' * 61 }) }).to eq('footer_too_long')
      expect(error_code { build(buttons: [{ type: 'QUICK_REPLY', text: 'a' * 26 }]) }).to eq('button_text_too_long')
    end

    it 'allows one variable in the header and none in the footer' do
      expect(error_code { build(header: { format: 'TEXT', text: '{{1}} {{2}}', examples: %w[a b] }) }).to eq('header_one_variable')
      expect(error_code { build(footer: { text: 'Hola {{1}}' }) }).to eq('footer_no_variables')
    end

    it 'needs the example file of a media header' do
      expect(error_code { build(header: { format: 'VIDEO' }) }).to eq('header_media_required')
      expect(error_code { build(header: { format: 'GIF' }) }).to eq('invalid_header_format')
    end

    it 'validates the buttons' do
      expect(error_code { build(buttons: [{ type: 'FLOW', text: 'Abrir' }]) }).to eq('invalid_button_type')
      expect(error_code { build(buttons: [{ type: 'QUICK_REPLY', text: '' }]) }).to eq('button_text_required')
      expect(error_code { build(buttons: [{ type: 'URL', text: 'Ver', url: 'ftp://x' }]) }).to eq('url_invalid')
      expect(error_code { build(buttons: [{ type: 'URL', text: 'Ver', url: 'https://x.com/{{1}}/y', examples: ['a'] }]) }).to eq('url_variable_at_end')
      expect(error_code { build(buttons: [{ type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '0999' }]) }).to eq('phone_invalid')
    end

    it 'limits how many buttons of each kind there can be' do
      many = Array.new(11) { { type: 'QUICK_REPLY', text: 'Ok' } }
      urls = Array.new(3) { { type: 'URL', text: 'Ver', url: 'https://example.com' } }
      phones = Array.new(2) { { type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+593999999999' } }

      expect(error_code { build(buttons: many) }).to eq('too_many_buttons')
      expect(error_code { build(buttons: urls) }).to eq('too_many_url_buttons')
      expect(error_code { build(buttons: phones) }).to eq('too_many_phone_buttons')
    end
  end
end
