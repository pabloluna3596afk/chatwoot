require 'rails_helper'

RSpec.describe Captain::TemplateMessage do
  let(:numbered) do
    { 'name' => 'recordatorio', 'language' => 'es', 'status' => 'approved', 'category' => 'UTILITY', 'namespace' => 'ns',
      'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}, tu cita {{2}} es el {{3}} a las {{4}}. Hasta {{1}}.' }] }
  end
  let(:named) do
    { 'name' => 'cita', 'language' => 'es', 'status' => 'approved', 'parameter_format' => 'NAMED',
      'components' => [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Cita: {{titulo}}' },
                       { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, es el {{fecha}}.' },
                       { 'type' => 'FOOTER', 'text' => 'Gracias {{nada}}' }] }
  end
  let(:drops) do
    { 'contact' => { 'name' => 'Ana Pérez' }, 'assistant' => { 'name' => 'Aurora' },
      'appointment' => { 'date' => 'martes 15 de enero', 'time' => '10:00', 'title' => 'Consulta' } }
  end

  describe '.variables' do
    it 'lists the numbered variables of the body once each, in order' do
      expect(described_class.variables(numbered).map(&:key)).to eq(%w[body.1 body.2 body.3 body.4])
    end

    it 'lists the named variables of a text header and of the body, and none of the footer' do
      expect(described_class.variables(named).map(&:key)).to eq(%w[header.titulo body.nombre body.fecha])
    end

    it 'ignores a header that is an image or a document' do
      media = named.merge('components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Hola {{1}}' }])

      expect(described_class.variables(media).map(&:key)).to eq(['body.1'])
    end

    it 'finds none in a template without variables' do
      expect(described_class.variables('components' => [{ 'type' => 'BODY', 'text' => 'Hola' }])).to be_empty
    end
  end

  describe '.unmapped' do
    it 'names the variables with no text, or only blanks' do
      params = { 'body' => { '1' => '{{ contact.name }}', '2' => '  ' } }

      expect(described_class.unmapped(numbered, params)).to eq(%w[body.2 body.3 body.4])
    end

    it 'counts everything as unmapped without texts' do
      expect(described_class.unmapped(numbered, nil)).to eq(%w[body.1 body.2 body.3 body.4])
    end
  end

  describe '.build' do
    it 'renders the Liquid of each variable, wherever the order is, in the body and in the header' do
      params = { 'header' => { 'titulo' => '{{ appointment.title }}' },
                 'body' => { 'nombre' => '{{ contact.name }}', 'fecha' => '{{ appointment.date }} a las {{ appointment.time }}' } }

      payload, text = described_class.build(named, params, drops)

      expect(text).to eq('Hola Ana Pérez, es el martes 15 de enero a las 10:00.')
      expect(payload).to include(name: 'cita', language: 'es')
      expect(payload[:processed_params]).to eq(header: { 'titulo' => 'Consulta' },
                                               body: { 'nombre' => 'Ana Pérez', 'fecha' => 'martes 15 de enero a las 10:00' })
    end

    it 'fills numbered variables, and a fixed text is just a text without Liquid' do
      params = { 'body' => { '1' => '{{ appointment.title }}', '2' => '{{ contact.name }}', '3' => '{{ appointment.time }}', '4' => 'hoy' } }

      payload, text = described_class.build(numbered, params, drops)

      expect(text).to eq('Hola Consulta, tu cita Ana Pérez es el 10:00 a las hoy. Hasta Consulta.')
      expect(payload).to include(namespace: 'ns', category: 'UTILITY')
      expect(payload[:processed_params]).to eq(body: { '1' => 'Consulta', '2' => 'Ana Pérez', '3' => '10:00', '4' => 'hoy' })
    end

    it 'sends "-" for a text that renders empty (Meta rejects empty variables)' do
      params = { 'body' => { '1' => '{{ contact.name }}', '2' => '{{ appointment.nope }}', '3' => '{{ appointment.date }}', '4' => 'x' } }

      payload, = described_class.build(numbered, params, drops)

      expect(payload[:processed_params][:body]).to eq('1' => 'Ana Pérez', '2' => '-', '3' => 'martes 15 de enero', '4' => 'x')
    end

    it 'raises when a variable of the template has no text (the template changed in Meta)' do
      expect { described_class.build(numbered, { 'body' => { '1' => '{{ contact.name }}' } }, drops) }
        .to raise_error(described_class::MappingMismatch, /body\.2/)
    end

    it 'uses the fallback texts for a template saved before the variables could be chosen (nil)' do
      fallback = { 'body' => { '1' => '{{ contact.name }}', '2' => '{{ appointment.title }}', '3' => '{{ appointment.date }}',
                               '4' => '{{ appointment.time }}' } }

      _, text = described_class.build(numbered, nil, drops, fallback: fallback)

      expect(text).to eq('Hola Ana Pérez, tu cita Consulta es el martes 15 de enero a las 10:00. Hasta Ana Pérez.')
    end

    it 'falls back to the template name when it has no body text' do
      _, text = described_class.build({ 'name' => 'vacia', 'components' => [] }, {}, drops)

      expect(text).to eq('vacia')
    end
  end

  describe '.valid_liquid?' do
    it 'accepts plain text and expressions, and refuses a broken tag' do
      expect(described_class.valid_liquid?('Hola {{ contact.name }}')).to be(true)
      expect(described_class.valid_liquid?('hoy')).to be(true)
      expect(described_class.valid_liquid?('{% if %}')).to be(false)
    end
  end

  describe '.drops' do
    let(:account) { create(:account) }
    let(:assistant) { create(:captain_assistant, account: account, name: 'Aurora') }
    let(:conversation) { create(:conversation, account: account, contact: create(:contact, account: account, name: 'Ana Pérez')) }

    it 'gives the texts the contact, the account, the assistant and the appointment' do
      drops = described_class.drops(conversation, assistant, appointment: { date: 'jueves 1 de octubre', title: 'Consulta' })

      text = Liquid::Template.parse('{{ contact.name }} / {{ assistant.name }} / {{ appointment.date }} / {{ appointment.title }}').render(drops)
      expect(text).to eq('Ana Pérez / Aurora / jueves 1 de octubre / Consulta')
    end

    it 'has an empty appointment for messages that are not about one' do
      drops = described_class.drops(conversation, assistant)

      expect(Liquid::Template.parse('[{{ appointment.date }}]').render(drops)).to eq('[]')
    end
  end

  describe 'looking a template up' do
    let(:account) { create(:account) }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                message_templates: [numbered, numbered.merge('name' => 'pendiente', 'status' => 'pending')])
    end

    it 'finds the approved template of an inbox by name and language, whatever the case of the language' do
      expect(described_class.approved(channel.inbox, { 'name' => 'recordatorio', 'language' => 'ES' })).to eq(numbered)
    end

    it 'does not find one that is not approved, or one of an inbox that is not WhatsApp' do
      expect(described_class.approved(channel.inbox, { 'name' => 'pendiente', 'language' => 'es' })).to be_nil
      expect(described_class.approved(create(:inbox, account: account), { 'name' => 'recordatorio', 'language' => 'es' })).to be_nil
    end

    it 'finds, in the inboxes of the account, a template whatever its status (to check the texts on save)' do
      channel

      expect(described_class.find_in_account(account, { 'name' => 'pendiente', 'language' => 'es' })).to include('status' => 'pending')
      expect(described_class.find_in_account(create(:account), { 'name' => 'recordatorio', 'language' => 'es' })).to be_nil
    end
  end
end
