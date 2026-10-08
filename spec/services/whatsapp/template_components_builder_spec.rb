require 'rails_helper'

RSpec.describe Whatsapp::TemplateComponentsBuilder do
  def build(**parts)
    described_class.new(body: { text: 'Hola' }, **parts).components
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

  describe 'named variables' do
    def builder(**parts)
      described_class.new(body: { text: 'Hola' }, **parts)
    end

    it 'builds the examples as named params and reports the format' do
      template = builder(
        header: { format: 'TEXT', text: 'Cita de {{nombre}}', examples: ['Ana'] },
        body: { text: 'Hola {{nombre}}, tu cita {{cita}} es el {{fecha}} a las {{hora}}.', examples: ['Ana', 'Consulta', 'lunes', '10:30'] }
      )

      expect(template.parameter_format).to eq('NAMED')
      components = template.components
      expect(components[0][:example]).to eq(header_text_named_params: [{ param_name: 'nombre', example: 'Ana' }])
      expect(components[1][:example]).to eq(
        body_text_named_params: [
          { param_name: 'nombre', example: 'Ana' }, { param_name: 'cita', example: 'Consulta' },
          { param_name: 'fecha', example: 'lunes' }, { param_name: 'hora', example: '10:30' }
        ]
      )
    end

    it 'repeats a name once in the examples' do
      template = builder(body: { text: 'Hola {{nombre}}, adiós {{nombre}}. ¿Todo bien {{tema}}?', examples: %w[Ana pagos] })

      expect(template.components.first[:example][:body_text_named_params].map { |item| item[:param_name] }).to eq(%w[nombre tema])
    end

    it 'keeps numbered variables as before' do
      template = builder(body: { text: 'Hola {{1}}, adiós {{2}}.', examples: %w[Ana lunes] })

      expect(template.parameter_format).to eq('POSITIONAL')
      expect(template.components.first[:example]).to eq(body_text: [%w[Ana lunes]])
    end

    it 'is POSITIONAL without variables' do
      expect(builder.parameter_format).to eq('POSITIONAL')
    end

    it 'refuses a mix, a bad name, a missing example and an edge variable' do
      expect(error_code { builder(body: { text: 'Hola {{nombre}} y {{2}} fin', examples: %w[a b] }).components }).to eq('variables_mixed')
      expect(error_code { builder(body: { text: 'Hola {{Nombre}} fin', examples: ['a'] }).components }).to eq('variable_name_invalid')
      expect(error_code { builder(body: { text: 'Hola {{nombre}} y {{fecha}} fin', examples: ['a'] }).components }).to eq('example_required')
      expect(error_code { builder(body: { text: '{{nombre}} hola', examples: ['a'] }).components }).to eq('variable_at_edge')
      expect(error_code { builder(header: { format: 'TEXT', text: '{{a}} {{b}}', examples: %w[a b] }).components }).to eq('header_one_variable')
    end
  end

  describe 'the rules Meta enforces' do
    it 'asks for a body, an example per variable and variables in order' do
      expect(error_code { build(body: { text: ' ' }) }).to eq('body_required')
      expect(error_code { build(body: { text: 'Hola {{1}} y {{2}} gracias', examples: ['Ana'] }) }).to eq('example_required')
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
      middle_variable = { type: 'URL', text: 'Ver', url: 'https://x.com/{{1}}/y', examples: ['a'] }
      expect(error_code { build(buttons: [middle_variable]) }).to eq('url_variable_at_end')
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

  describe 'explicit parameter format' do
    it 'keeps NAMED for a new system copy with no text variables' do
      builder = described_class.new(body: { text: 'Tu pedido est? listo.' }, parameter_format: 'NAMED')

      expect(builder.components).to eq([{ type: 'BODY', text: 'Tu pedido est? listo.' }])
      expect(builder.parameter_format).to eq('NAMED')
    end

    it 'refuses a declared format that conflicts with the text' do
      builder = described_class.new(body: { text: 'Hola {{1}}, gracias.', examples: ['Ana'] }, parameter_format: 'NAMED')

      expect { builder.components }.to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('variables_mixed') }
    end
  end

  describe 'dynamic URL regression' do
    it 'keeps the exact positional URL from the approved template' do
      components = build(buttons: [{ type: 'URL', text: 'Seguir pedido', url: 'https://paluhub.com/track/{{2}}',
                                     examples: ['https://paluhub.com/track/123'] }])

      expect(components.last[:buttons].first).to eq(type: 'URL', text: 'Seguir pedido', url: 'https://paluhub.com/track/{{2}}',
                                                    example: ['https://paluhub.com/track/123'])
    end

    it 'requires a complete example with the same URL prefix' do
      expect do
        build(buttons: [{ type: 'URL', text: 'Seguir', url: 'https://paluhub.com/track/{{2}}', examples: ['123'] }])
      end.to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('url_example_invalid') }
    end
  end

  describe 'copy code button' do
    it 'builds the coupon button of a marketing template without a label' do
      components = described_class.new(body: { text: 'Hola' }, category: 'MARKETING', buttons: [{ type: 'COPY_CODE', code: ' PALU21 ' }]).components

      expect(components.last).to eq(type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', example: 'PALU21' }])
    end

    it 'is refused outside marketing, without a code, too long, or twice' do
      copy = { type: 'COPY_CODE', code: 'PALU21' }

      utility = described_class.new(body: { text: 'Hola' }, category: 'UTILITY', buttons: [copy])
      expect(error_code { utility.components }).to eq('copy_code_marketing_only')
      expect(error_code { build(buttons: [{ type: 'COPY_CODE', code: '' }]) }).to eq('copy_code_required')
      expect(error_code { build(buttons: [{ type: 'COPY_CODE', code: 'A' * 16 }]) }).to eq('copy_code_too_long')
      expect(error_code { build(buttons: [copy, copy]) }).to eq('too_many_copy_code')
    end
  end

  describe 'preserved parts' do
    let(:offer) { { type: 'LIMITED_TIME_OFFER', limited_time_offer: { text: 'Oferta', has_expiration: true } } }
    let(:flow) { { type: 'FLOW', text: 'Abrir', flow_id: '123' } }

    it 'puts back what the form cannot express, where it stood' do
      components = build(
        header: { format: 'TEXT', text: 'Hola' }, buttons: [{ type: 'QUICK_REPLY', text: 'Ok' }],
        preserved: { components: [{ position: 1, component: offer }], buttons: [{ position: 1, button: flow }] }
      )

      expect(components.pluck(:type)).to eq(%w[HEADER LIMITED_TIME_OFFER BODY BUTTONS])
      expect(components.last[:buttons]).to eq([{ type: 'QUICK_REPLY', text: 'Ok' }, flow])
      expect(components[1]).to eq(offer)
    end

    it 'keeps a template whose only button is a preserved one' do
      expect(build(preserved: { buttons: [{ position: 0, button: flow }] }).last).to eq(type: 'BUTTONS', buttons: [flow])
    end

    it 'refuses a preserved part the form builds itself, or without a type' do
      expect(error_code { build(preserved: { components: [{ position: 0, component: { type: 'BODY', text: 'x' } }] }) }).to eq('preserved_invalid')
      expect(error_code { build(preserved: { buttons: [{ position: 0, button: { text: 'x' } }] }) }).to eq('preserved_invalid')
    end
  end
end
