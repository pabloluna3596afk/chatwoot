require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::InvitationText do
  let(:account) { instance_double(Account, name: 'Clínica Sol', locale: 'es', appointment_location: 'Av. Amazonas 123, piso 2') }
  let(:contact) { instance_double(Contact, name: 'ana pérez', phone_number: '+593999999999', email: 'ana@example.com') }
  let(:conversation) { instance_double(Conversation, display_id: 42) }
  let(:start_at) { Time.utc(2030, 1, 17, 15, 30) }

  def values(**overrides)
    described_class.values_for(
      account: account, start_at: start_at, timezone: 'America/Guayaquil', contact: contact, conversation: conversation,
      agent_name: 'Pablo', summary: 'Consulta', **overrides
    )
  end

  describe '.render' do
    it 'fills the variables in, with or without spaces inside the braces' do
      text = described_class.render('Hola {{nombre}} y {{ agente }}', 'nombre' => 'Ana', 'agente' => 'Pablo')

      expect(text).to eq('Hola Ana y Pablo')
    end

    it 'leaves what is not a known variable as it was typed' do
      expect(described_class.render('Hola {{nobre}} {{nombre}}', 'nombre' => 'Ana')).to eq('Hola {{nobre}} Ana')
    end

    it 'leaves out a line whose variables are all empty, and keeps one that has some value' do
      template = "Fecha: {{fecha}}\nLugar: {{direccion}}\nVideollamada: {{enlace_meet}}\n{{fecha}} {{direccion}}"

      expect(described_class.render(template, 'fecha' => 'jueves', 'direccion' => '', 'enlace_meet' => '')).to eq("Fecha: jueves\njueves")
    end

    it 'keeps the lines that have no variables and does not leave more than one blank line' do
      template = "Hola\n\n\n{{direccion}}\n\n\nAdiós\n"

      expect(described_class.render(template, 'direccion' => '')).to eq("Hola\n\nAdiós")
    end

    it 'reads text written on Windows' do
      expect(described_class.render("a\r\n{{nombre}}", 'nombre' => 'Ana')).to eq("a\nAna")
    end
  end

  describe '.values_for' do
    it 'gives each variable its value, with the date and time in the account zone and language' do
      result = values

      expect(result).to include(
        'nombre' => 'ana pérez', 'primer_nombre' => 'Ana', 'telefono' => '+593999999999', 'correo' => 'ana@example.com',
        'agente' => 'Pablo', 'empresa' => 'Clínica Sol', 'fecha' => 'jueves 17 de enero', 'hora' => '10:30',
        'motivo' => 'Consulta', 'direccion' => 'Av. Amazonas 123, piso 2', 'enlace_meet' => '', 'conversacion' => '#42'
      )
    end

    it 'writes the date in English for an English account' do
      english = instance_double(Account, name: 'Sun', locale: 'en', appointment_location: nil)

      result = described_class.values_for(account: english, start_at: start_at, timezone: 'America/Guayaquil')

      expect(result['fecha']).to eq('Thursday, January 17')
      expect(result['direccion']).to eq('')
      expect(result['nombre']).to eq('')
    end

    it 'takes the Meet link when there is one' do
      expect(values(meet_link: 'https://meet.google.com/abc')['enlace_meet']).to eq('https://meet.google.com/abc')
    end
  end

  describe 'the account text' do
    it 'is the default one until the account writes its own' do
      plain = instance_double(Account, appointment_invitation_template: nil, locale: 'es')
      own = instance_double(Account, appointment_invitation_template: 'Te esperamos', locale: 'es')

      expect(described_class.template_for(plain)).to include('{{primer_nombre}}', '{{enlace_meet}}')
      expect(described_class.template_for(plain)).not_to include('x')
      expect(described_class.template_for(own)).to eq('Te esperamos')
    end

    it 'has a default text for every language the app writes it in, using only known variables' do
      %w[es en].each do |locale|
        text = described_class.default_template(locale)

        expect(text).to be_present
        expect(described_class.unknown_tokens(text)).to eq([])
      end
    end
  end

  describe '.unknown_tokens and .uses?' do
    it 'lists the variables that do not exist, once each' do
      expect(described_class.unknown_tokens('{{nombre}} {{nobre}} {{nobre}} {{x}}')).to eq(%w[nobre x])
    end

    it 'says whether a variable is used' do
      expect(described_class.uses?('Link: {{ enlace_meet }}', 'enlace_meet')).to be true
      expect(described_class.uses?('Hola', 'enlace_meet')).to be false
    end
  end
end
