require 'rails_helper'

RSpec.describe 'Captain messaging tools' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, locale: 'es') }
  let(:templates) do
    [{ 'name' => 'cita_confirmada', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'ns',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}, soy {{asistente}}.' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let(:flow) { create(:whatsapp_flow, account: account, name: 'Datos de reserva') }
  let(:params) { { 'body' => { 'nombre' => '{{ contact.first_name }}', 'asistente' => '{{ assistant.name }}' } } }
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
                                    status: 'published', meta_flow_id: '1234567', published_at: Time.current)
    allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(true) # rubocop:disable RSpec/AnyInstance
  end

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_MESSAGING_INTENT, conversation_id: conversation.id)) }

  def prepared_request
    Captain::Messaging::Intent.take(conversation, responding_to: customer_message.id)
  end

  describe Captain::Tools::ListAvailableFlowsTool do
    it 'lists the allowed Flows that are published, with their purpose and the fields they ask' do
      data = JSON.parse(described_class.new(assistant).perform(tool_context))

      expect(data['window_open']).to be(true)
      expect(data['flows']).to eq([{ 'flow_id' => flow.id, 'name' => 'Datos de reserva', 'purpose' => 'Pedir datos',
                                     'fields' => [{ 'label' => 'Nombre', 'type' => 'short_text' }], 'can_send' => true }])
    end

    it 'says why a Flow cannot be sent' do
      flow.whatsapp_flow_publications.destroy_all

      entry = JSON.parse(described_class.new(assistant).perform(tool_context))['flows'].first

      expect(entry).to include('can_send' => false, 'reason' => 'El Flow no está publicado o la plantilla no está aprobada para esta bandeja.')
    end

    it 'does not work outside a real conversation or where the owner did not allow it' do
      expect(described_class.new(assistant).perform(Struct.new(:state).new({ conversation: { id: conversation.id } })))
        .to eq('Los formularios y las plantillas solo se pueden enviar en una conversación real.')

      assistant.captain_inboxes.destroy_all
      expect(described_class.new(assistant).perform(tool_context)).to include('no habilitó')
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
        travel_to(Time.zone.parse('2030-01-15T10:05:00-05:00'))

        result = described_class.new(assistant).perform(tool_context, flow_id: flow.id, customer_asked_again: true)

        expect(result).to include('límite de envíos', 'unos 5 minutos')
      end
    end

    it 'rejects what is not a Flow id' do
      expect(described_class.new(assistant).perform(tool_context, flow_id: 'abc')).to include('formato requerido')
    end
  end

  describe Captain::Tools::ListAvailableTemplatesTool do
    it 'lists the allowed templates and whether they can be sent' do
      entry = JSON.parse(described_class.new(assistant).perform(tool_context))['templates'].first

      expect(entry).to eq('name' => 'cita_confirmada', 'language' => 'es', 'purpose' => 'Confirmar', 'can_send' => true)
    end

    it 'says paid messages are off' do
      assistant.update!(config: assistant.config.merge('allow_paid_templates' => false))

      entry = JSON.parse(described_class.new(assistant).perform(tool_context))['templates'].first

      expect(entry).to include('can_send' => false, 'reason' => 'Los mensajes de pago están desactivados.')
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

      expect(result).to eq('Los mensajes de pago están desactivados.')
      expect(prepared_request).to be_nil
    end
  end
end
