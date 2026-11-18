require 'rails_helper'

RSpec.describe 'Captain messaging tools' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, locale: 'es') }
  let(:templates) do
    [{ 'name' => 'cita_confirmada', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'ns',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}, soy {{asistente}}.' }],
       'processed_params' => params }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let(:flow) do
    create(:whatsapp_flow, account: account, name: 'Datos de reserva', definition: {
             'schema_version' => 1, 'screens' => [{ 'title' => 'Tus datos', 'button' => 'Enviar', 'blocks' => [
               { 'type' => 'heading', 'text' => 'Reserva una consulta' },
               { 'type' => 'short_text', 'key' => 'nombre', 'label' => 'Nombre', 'required' => true }
             ] }]
           })
  end
  let(:params) { { 'body' => { 'nombre' => '{{ contact.name }}', 'asistente' => '{{ assistant.name }}' } } }
  let(:messaging) do
    { 'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true,
                      'flows' => [{ 'flow_id' => flow.id, 'purpose' => 'Pedir datos' }],
                      'templates' => [{ 'name' => 'cita_confirmada', 'language' => 'es', 'purpose' => 'Confirmar',
                                        'processed_params' => params }] }] }
  end
  let(:assistant) do
    create(:captain_assistant, account: account, name: 'Aurora', config: { 'messaging' => messaging, 'allow_paid_templates' => true })
  end
  let!(:customer_message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
  end
  let(:state) { { conversation: { id: conversation.id }, responding_to_message_id: customer_message.id } }
  let(:tool_context) { Struct.new(:state).new(state) }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    WhatsappFlowPublication.create!(whatsapp_flow: flow, account: account, waba_id: channel.provider_config['business_account_id'],
                                    status: 'published', meta_flow_id: '1234567', published_version: 1, published_at: Time.current)
    allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(true) # rubocop:disable RSpec/AnyInstance
  end

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_MESSAGING_INTENT, conversation_id: conversation.id)) }

  def prepared_request
    Captain::Messaging::Intent.take(conversation, responding_to: customer_message.id)
  end

  describe Captain::Tools::FlowCatalogTool do
    it 'lists the allowed Flows that are published, with their purpose and the fields they ask' do
      data = JSON.parse(described_class.new(assistant).perform(tool_context))

      expect(data['window_open']).to be(true)
      expect(data['flows']).to eq([{ 'flow_id' => flow.id, 'name' => 'Datos de reserva', 'purpose' => 'Pedir datos',
                                     'fields' => [{ 'label' => 'Nombre', 'type' => 'short_text' }],
                                     'first_screen' => { 'title' => 'Tus datos', 'text' => 'Reserva una consulta',
                                                         'button' => 'Enviar', 'truncated' => false },
                                     'can_send' => true }])
    end

    it 'omits unpublished Flows from the eligible catalog' do
      flow.whatsapp_flow_publications.destroy_all

      expect(JSON.parse(described_class.new(assistant).perform(tool_context))['flows']).to be_empty
    end

    it 'returns an empty catalog when the Cloud inbox has no WABA id' do
      channel.update!(provider_config: { 'api_key' => 'token' })

      expect(JSON.parse(described_class.new(assistant).perform(tool_context))['flows']).to be_empty
    end

    it 'does not work outside a real conversation or where the owner did not allow it' do
      expect(described_class.new(assistant).perform(Struct.new(:state).new({ conversation: { id: conversation.id } })))
        .to eq('Los formularios y las plantillas solo se pueden enviar en una conversación real.')

      assistant.captain_inboxes.destroy_all
      expect(described_class.new(assistant).perform(tool_context)).to include('no habilitó')
    end
  end

  %w[list auto].each do |mode|
    context "when catalogs use #{mode} mode" do
      before do
        config = assistant.config.deep_dup
        entry = config.fetch('messaging').fetch('inboxes').first
        if mode == 'auto'
          Captain::Messaging::LegacyEntryConverter.new(assistant, entry).perform
          config['messaging'].merge!('version' => 2, 'revision' => 1)
        end
        assistant.update!(config: config)
      end

      it 'includes template content, variables and the existing owner note' do
        data = JSON.parse(Captain::Tools::TemplateCatalogTool.new(assistant).perform(tool_context))
        expect(data['templates'].first).to include(
          'text' => 'Hola {{nombre}}, soy {{asistente}}.', 'purpose' => 'Confirmar', 'can_send' => true,
          'variables' => [{ 'component' => 'body', 'name' => 'nombre' }, { 'component' => 'body', 'name' => 'asistente' }]
        )
      end

      it 'provides header, footer, buttons and numbered variables without requiring a note' do
        components = [
          { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Reserva {{1}}' },
          { 'type' => 'BODY', 'text' => 'Tu cita' }, { 'type' => 'FOOTER', 'text' => 'Gracias' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Confirmar' }] }
        ]
        channel.update!(message_templates: [templates.first.merge('components' => components)])
        config = assistant.config.deep_dup
        entry = config.fetch('messaging').fetch('inboxes').first
        if mode == 'auto'
          entry['notes'] = {}
          key = "#{channel.provider_config['business_account_id']}:cita_confirmada|es"
          entry['params'] = { key => { 'header' => { '1' => '{{ contact.name }}' } } }
          entry['reviewed'] = Captain::Messaging::Review.new(assistant, inbox.reload).activation_snapshot
        else
          entry['templates'].first.delete('purpose')
          entry['templates'].first['processed_params'] = { 'header' => { '1' => '{{ contact.name }}' } }
        end
        assistant.update!(config: config)

        data = JSON.parse(Captain::Tools::TemplateCatalogTool.new(assistant).perform(tool_context))['templates'].first
        expect(data).to include('header' => 'Reserva {{1}}', 'text' => 'Tu cita', 'footer' => 'Gracias',
                                'buttons' => ['Confirmar'], 'variables' => [{ 'component' => 'header', 'name' => '1' }],
                                'category' => 'UTILITY', 'language' => 'es', 'truncated' => false, 'can_send' => true)
        expect(data).not_to have_key('purpose')
      end

      it 'lists all enabled templates and marks a long body as truncated' do
        channel.update!(message_templates: Array.new(21) do |index|
          templates.first.merge('name' => "template_#{index}", 'components' => [{ 'type' => 'BODY', 'text' => 'a' * 1200 }])
        end)
        config = assistant.config.deep_dup
        entry = config.fetch('messaging').fetch('inboxes').first
        if mode == 'auto'
          entry['reviewed'] = Captain::Messaging::Review.new(assistant, inbox.reload).activation_snapshot
        else
          entry['templates'] = channel.message_templates.map { |item| item.slice('name', 'language').merge('processed_params' => {}) }
        end
        assistant.update!(config: config)

        items = JSON.parse(Captain::Tools::TemplateCatalogTool.new(assistant).perform(tool_context))['templates']
        expect(items.size).to eq(21)
        expect(items).to all(include('truncated' => true, 'can_send' => true))
        expect(items.map { |item| item['text'].length }).to all(eq(1000))
      end

      it 'includes Flow content and fields with or without an owner note' do
        tool = Captain::Tools::FlowCatalogTool.new(assistant)
        item = JSON.parse(tool.perform(tool_context))['flows'].first
        expect(item).to include('purpose' => 'Pedir datos', 'name' => 'Datos de reserva')

        config = assistant.config.deep_dup
        entry = config.fetch('messaging').fetch('inboxes').first
        mode == 'auto' ? entry['notes'] = {} : entry['flows'].first.delete('purpose')
        assistant.update!(config: config)
        item = JSON.parse(tool.perform(tool_context))['flows'].first
        expect(item).to include('first_screen' => { 'title' => 'Tus datos', 'text' => 'Reserva una consulta',
                                                    'button' => 'Enviar', 'truncated' => false },
                                'fields' => [{ 'label' => 'Nombre', 'type' => 'short_text' }], 'can_send' => true)
        expect(item).not_to have_key('purpose')
      end
    end
  end

  describe Captain::Tools::SendFlowTool do
    it 'prepares the Flow for the reply and sends nothing yet' do
      result = nil
      expect { result = described_class.new(assistant).perform(tool_context, flow_id: flow.id, intro_text: 'Completa tus datos') }
        .not_to change(Message, :count)

      expect(result).to include('El formulario está preparado')
      request = prepared_request
      expect(request).to have_attributes(kind: 'flow', resource: flow.id, intro_text: 'Completa tus datos', resend_requested: false,
                                         responding_to_message_id: customer_message.id)
    end

    it 'prepares only one send per customer message' do
      described_class.new(assistant).perform(tool_context, flow_id: flow.id)

      expect(described_class.new(assistant).perform(tool_context, flow_id: flow.id)).to include('Ya hay un formulario')
    end

    it 'tells the model when the Flow is not allowed, and prepares nothing' do
      other = create(:whatsapp_flow, account: account)

      expect(described_class.new(assistant).perform(tool_context, flow_id: other.id)).to eq('Este recurso no está autorizado.')
      expect(prepared_request).to be_nil
    end

    it 'tells the model a Flow is already pending and when it can try again' do
      travel_to(Time.zone.parse('2030-01-15T10:00:00-05:00')) do
        Captain::Messaging::SendService.new(
          conversation: conversation, assistant: assistant,
          request: Captain::Messaging::Request.new(kind: 'flow', resource: flow.id, responding_to_message_id: customer_message.id - 1)
        ).perform
        travel(5.minutes)

        result = described_class.new(assistant).perform(tool_context, flow_id: flow.id, customer_asked_again: true)

        expect(result).to include('límite de envíos', 'unos 5 minutos')
      end
    end

    it 'rejects what is not a Flow id' do
      expect(described_class.new(assistant).perform(tool_context, flow_id: 'abc')).to include('formato requerido')
    end
  end

  describe Captain::Tools::TemplateCatalogTool do
    it 'lists the allowed templates and whether they can be sent' do
      entry = JSON.parse(described_class.new(assistant).perform(tool_context))['templates'].first

      expect(entry).to include('name' => 'cita_confirmada', 'language' => 'es', 'purpose' => 'Confirmar', 'can_send' => true)
    end

    it 'says paid messages are off' do
      assistant.update!(config: assistant.config.merge('allow_paid_templates' => false))

      entry = JSON.parse(described_class.new(assistant).perform(tool_context))['templates'].first

      expect(entry).to include('can_send' => false, 'reason' => 'Las plantillas están desactivadas para este asistente.')
    end
  end

  describe Captain::Tools::SendTemplateTool do
    it 'prepares the template for the reply and sends nothing yet' do
      result = nil
      expect { result = described_class.new(assistant).perform(tool_context, template_name: 'cita_confirmada', language: 'es') }
        .not_to change(Message, :count)

      expect(result).to include('La plantilla está preparada')
      expect(prepared_request).to have_attributes(kind: 'template', resource: { name: 'cita_confirmada', language: 'es' })
    end

    it 'does not prepare a template when paid messages are off' do
      assistant.update!(config: assistant.config.merge('allow_paid_templates' => false))

      result = described_class.new(assistant).perform(tool_context, template_name: 'cita_confirmada', language: 'es')

      expect(result).to eq('Las plantillas están desactivadas para este asistente.')
      expect(prepared_request).to be_nil
    end
  end

  describe 'how the assistant finds them' do
    it 'resolves the id of every tool of the registry to a class (a plural id such as "x_flows" would not)' do
      Captain::Assistant.built_in_tool_ids.each do |tool_id|
        expect(Captain::Assistant.resolve_tool_class(tool_id)).to be_present, "#{tool_id} has no tool class"
      end
    end

    it 'builds the four tools' do
      expect(assistant.messaging_tools.map { |tool| tool.class.name.demodulize })
        .to eq(%w[FlowCatalogTool SendFlowTool TemplateCatalogTool SendTemplateTool])
    end

    it 'gives them to the agent of a real conversation of an inbox the owner allowed, and to no other' do
      run_options = Captain::Assistant::AgentRunnerService::RunOptions.new(responding_to_message_id: customer_message.id)
      runner = Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conversation, run_options: run_options)
      names = ->(agent) { agent.tools.map { |tool| tool.class.name.demodulize } }

      expect(names.call(runner.send(:with_messaging_tools, assistant.agent))).to include('FlowCatalogTool', 'SendFlowTool', 'SendTemplateTool')

      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      other_runner = Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: other, run_options: run_options)
      expect(names.call(other_runner.send(:with_messaging_tools, assistant.agent))).not_to include('SendFlowTool')
    end
  end
end
