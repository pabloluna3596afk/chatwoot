require 'rails_helper'

RSpec.describe Captain::Messaging::SendService do
  let(:account) { create(:account, locale: 'es') }
  let(:templates) do
    [{ 'name' => 'cita_confirmada', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY', 'namespace' => 'ns',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}, soy {{asistente}}.' }] },
     { 'name' => 'pendiente', 'language' => 'es', 'status' => 'PENDING', 'components' => [{ 'type' => 'BODY', 'text' => 'Hola' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:flow) { create(:whatsapp_flow, account: account, name: 'Datos de reserva') }
  let(:params) { { 'body' => { 'nombre' => '{{ contact.first_name }}', 'asistente' => '{{ assistant.name }}' } } }
  let(:messaging) do
    { 'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true,
                      'flows' => [{ 'flow_id' => flow.id, 'purpose' => 'Pedir datos' }],
                      'templates' => [{ 'name' => 'cita_confirmada', 'language' => 'es', 'purpose' => 'Confirmar',
                                        'processed_params' => params }] }] }
  end
  let(:assistant_config) { { 'messaging' => messaging, 'allow_paid_templates' => true } }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Aurora', config: assistant_config) }
  let(:now) { Time.zone.parse('2030-01-15T10:00:00-05:00') }

  around { |example| travel_to(now) { example.run } }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    WhatsappFlowPublication.create!(whatsapp_flow: flow, account: account, waba_id: channel.provider_config['business_account_id'],
                                    status: 'published', meta_flow_id: '1234567', published_at: now)
    allow(conversation).to receive(:can_reply?).and_return(true)
  end

  def customer_says(at = now)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact, created_at: at)
  end

  def perform(kind, resource, responding_to, at: now, **)
    request = Captain::Messaging::Request.new(kind: kind, resource: resource, responding_to_message_id: responding_to, **)
    described_class.new(conversation: conversation, assistant: assistant, request: request, now: at).perform
  end

  def send_flow(responding_to: customer_says.id, at: now, **)
    perform('flow', flow.id, responding_to, at: at, **)
  end

  def send_template(responding_to: customer_says.id, name: 'cita_confirmada', **)
    perform('template', { name: name, language: 'es' }, responding_to, **)
  end

  def public_messages
    conversation.messages.where(private: false, message_type: :outgoing)
  end

  describe 'what the owner allows' do
    it 'sends nothing when the assistant has no messaging settings' do
      assistant.update!(config: {})

      expect(send_flow).to have_attributes(status: :denied, code: 'disabled')
      expect(public_messages).to be_empty
    end

    it 'sends nothing when the inbox switch is off' do
      messaging['inboxes'][0]['enabled'] = false
      assistant.update!(config: assistant_config)

      expect(send_flow.code).to eq('disabled')
    end

    it 'sends nothing when the assistant is not connected to the inbox' do
      assistant.captain_inboxes.destroy_all

      expect(send_flow.code).to eq('disabled')
    end

    it 'sends nothing on an inbox that is not WhatsApp' do
      web = create(:inbox, account: account)
      create(:captain_inbox, captain_assistant: assistant, inbox: web)
      web_conversation = create(:conversation, account: account, inbox: web)

      request = Captain::Messaging::Request.new(kind: 'flow', resource: flow.id, responding_to_message_id: 1)
      result = described_class.new(conversation: web_conversation, assistant: assistant, request: request, now: now).perform

      expect(result.code).to eq('disabled')
    end

    it 'refuses a Flow or a template that is not on the list' do
      other = create(:whatsapp_flow, account: account)
      flow_result = perform('flow', other.id, 1)

      expect(flow_result.code).to eq('not_allowed')
      expect(send_template(name: 'otra').code).to eq('not_allowed')
    end

    it 'refuses what is not a Flow id or a template reference' do
      result = perform('flow', 'abc', 1)

      expect(result.code).to eq('invalid_params')
    end
  end

  describe 'sending a Flow' do
    it 'creates the Flow message from Captain, with its audit record and a private note' do
      customer = customer_says
      result = send_flow(responding_to: customer.id)

      expect(result).to be_sent
      message = result.message
      expect(message.sender).to eq(assistant)
      expect(message.additional_attributes).to include('whatsapp_flow' => hash_including('id' => flow.id, 'name' => 'Datos de reserva'))
      expect(message.additional_attributes['captain_messaging']).to include(
        'assistant_id' => assistant.id, 'responding_to_message_id' => customer.id, 'kind' => 'flow', 'resource' => flow.id.to_s
      )
      note = conversation.messages.where(private: true).last
      expect(note.content).to eq('Captain envió el Flow Datos de reserva')
      expect(note.sender).to eq(assistant)
    end

    it 'uses the intro text as the message' do
      result = send_flow(intro_text: 'Completa tus datos para continuar.')

      expect(result.message.content).to eq('Completa tus datos para continuar.')
    end

    it 'refuses an intro text that is empty or too long' do
      expect(send_flow(intro_text: '').code).to eq('invalid_params')
      expect(send_flow(intro_text: 'a' * 1025).code).to eq('invalid_params')
    end

    it 'refuses a Flow that is not published any more' do
      flow.whatsapp_flow_publications.destroy_all

      expect(send_flow.code).to eq('unavailable')
      expect(public_messages).to be_empty
    end

    it 'refuses outside the 24 h window' do
      allow(conversation).to receive(:can_reply?).and_return(false)

      expect(send_flow.code).to eq('window_closed')
    end

    it 'does not send the same thing twice for the same customer message' do
      customer = customer_says
      first = send_flow(responding_to: customer.id)
      again = send_flow(responding_to: customer.id)

      expect(again).to be_duplicate
      expect(again.message).to eq(first.message)
      expect(conversation.messages.where("additional_attributes -> 'captain_messaging' IS NOT NULL").count).to eq(1)
    end
  end

  describe 'the limits of a conversation' do
    it 'does not send another Flow while one waits for its answer' do
      send_flow
      travel_to(now + 1.hour)
      expect(send_flow(at: Time.current).code).to eq('pending_flow')
    end

    it 'sends another Flow once the answer was saved and 10 minutes passed' do
      send_flow
      travel_to(now + 11.minutes)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                       content_attributes: { 'whatsapp_flow_saved' => true })

      expect(send_flow(at: Time.current)).to be_sent
    end

    it 'sends the pending Flow again when the customer asked for it, but not before 10 minutes' do
      send_flow
      travel_to(now + 5.minutes)
      result = send_flow(at: Time.current, resend_requested: true)

      expect(result).to have_attributes(code: 'rate_limit', retry_after: 300)
      travel_to(now + 11.minutes)
      expect(send_flow(at: Time.current, resend_requested: true)).to be_sent
    end

    it 'sends at most 3 Flows in 24 hours' do
      3.times do |index|
        travel_to(now + (index * 15).minutes)
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                         content_attributes: { 'whatsapp_flow_saved' => true })
        expect(send_flow(at: Time.current)).to be_sent
      end
      travel_to(now + 2.hours)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                       content_attributes: { 'whatsapp_flow_saved' => true })

      expect(send_flow(at: Time.current).code).to eq('rate_limit')
      travel_to(now + 25.hours)
      expect(send_flow(at: Time.current)).to be_sent
    end
  end

  describe 'sending a template' do
    it 'creates the template message from the texts the owner saved for each variable' do
      result = send_template

      expect(result).to be_sent
      message = result.message
      expect(message.content).to eq('Hola Ana, soy Aurora.')
      expect(message.sender).to eq(assistant)
      expect(message.additional_attributes['template_params']).to include(
        'name' => 'cita_confirmada', 'language' => 'es', 'processed_params' => { 'body' => { 'nombre' => 'Ana', 'asistente' => 'Aurora' } }
      )
      expect(message.additional_attributes['captain_messaging']).to include('kind' => 'template', 'resource' => 'cita_confirmada|es')
      expect(conversation.messages.where(private: true).last.content).to eq('Captain envió la plantilla cita_confirmada')
    end

    it 'needs the paid messages switch' do
      assistant.update!(config: assistant_config.merge('allow_paid_templates' => false))

      expect(send_template.code).to eq('paid_off')
      expect(public_messages).to be_empty
    end

    it 'refuses a template that is not approved' do
      messaging['inboxes'][0]['templates'] << { 'name' => 'pendiente', 'language' => 'es', 'processed_params' => {} }
      assistant.update!(config: assistant_config)

      expect(send_template(name: 'pendiente').code).to eq('unavailable')
    end

    it 'refuses a template with a variable that has no value' do
      messaging['inboxes'][0]['templates'][0]['processed_params'] = { 'body' => { 'nombre' => '{{ contact.first_name }}' } }
      assistant.update!(config: assistant_config)

      expect(send_template).to have_attributes(code: 'missing_variables', detail: 'body.asistente')
    end

    it 'sends at most one template in 24 hours' do
      send_template
      travel_to(now + 2.hours)
      expect(send_template(responding_to: customer_says(Time.current).id).code).to eq('rate_limit')
    end

    it 'sends a template inside the 24 h window too (it is a paid message, the owner allowed it)' do
      expect(send_template).to be_sent
    end
  end

  describe 'the daily cap of the account' do
    it 'sends nothing when the cap is reached, and counts the sends it makes' do
      account.update!(settings: (account.settings || {}).merge('proactive_daily_send_cap' => 1))

      expect(send_flow).to be_sent
      travel_to(now + 11.minutes)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                       content_attributes: { 'whatsapp_flow_saved' => true })

      expect(send_flow(at: Time.current).code).to eq('rate_limit')
      expect(Automations::ProactiveSendCap.new(account).within_cap?).to be(false)
    end

    it 'gives the place back when the message is not created' do
      allow_any_instance_of(Whatsapp::Flows::SendFlowService).to receive(:perform).and_raise(Whatsapp::Flows::SendFlowService::Error) # rubocop:disable RSpec/AnyInstance

      expect(send_flow.code).to eq('unavailable')
      expect(Automations::ProactiveSendCap.new(account).send(:current_count)).to eq(0)
    end
  end
end
