require 'rails_helper'

RSpec.describe Captain::MessagingValidator do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:flow) { create(:whatsapp_flow, account: account) }

  def assign(messaging)
    assistant.config = assistant.config.merge('messaging' => messaging)
  end

  def messaging_errors
    assistant.valid?
    assistant.errors[:config].select { |message| message.start_with?('messaging') }
  end

  it 'is valid without any messaging block: Captain sends nothing by default' do
    expect(messaging_errors).to be_empty
  end

  it 'accepts the allowed Flows and templates of a WhatsApp inbox, with a purpose' do
    assign('inboxes' => [{
             'inbox_id' => inbox.id, 'enabled' => true,
             'flows' => [{ 'flow_id' => flow.id, 'purpose' => 'Pedir los datos' }],
             'templates' => [{ 'name' => 'reserva', 'language' => 'es', 'purpose' => 'Confirmar' }]
           }])

    expect(messaging_errors).to be_empty
  end

  it 'accepts an empty inbox list' do
    assign('inboxes' => [])

    expect(messaging_errors).to be_empty
  end

  it 'needs every inbox switch to be true or false' do
    assign('inboxes' => [{ 'inbox_id' => inbox.id, 'flows' => [], 'templates' => [] }])

    expect(messaging_errors).to include('messaging inbox enabled must be true or false')
  end

  it 'rejects unknown keys so nothing can widen a permission' do
    assign('inboxes' => [], 'allow_all' => true)

    expect(messaging_errors.join).to include('unknown keys: allow_all')
  end

  it 'rejects an inbox of another account' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', account: create(:account),
                                      sync_templates: false, validate_provider_config: false)
    assign('inboxes' => [{ 'enabled' => true, 'inbox_id' => other.inbox.id, 'flows' => [], 'templates' => [] }])

    expect(messaging_errors.join).to include('must be an inbox of this account')
  end

  it 'rejects an inbox that is not WhatsApp' do
    web = create(:inbox, account: account)
    assign('inboxes' => [{ 'enabled' => true, 'inbox_id' => web.id, 'flows' => [], 'templates' => [] }])

    expect(messaging_errors.join).to include('must be a WhatsApp inbox')
  end

  it 'rejects a Flow of another account' do
    foreign = create(:whatsapp_flow, account: create(:account))
    assign('inboxes' => [{ 'enabled' => true, 'inbox_id' => inbox.id, 'flows' => [{ 'flow_id' => foreign.id }], 'templates' => [] }])

    expect(messaging_errors.join).to include('must be a Flow of this account')
  end

  it 'rejects repeated inboxes, Flows and templates' do
    assign('inboxes' => [
             { 'inbox_id' => inbox.id, 'enabled' => true, 'flows' => [{ 'flow_id' => flow.id }, { 'flow_id' => flow.id }],
               'templates' => [{ 'name' => 'a', 'language' => 'es' }, { 'name' => 'a', 'language' => 'es' }] },
             { 'inbox_id' => inbox.id, 'enabled' => true, 'flows' => [], 'templates' => [] }
           ])

    expect(messaging_errors).to include('messaging inboxes cannot repeat an inbox',
                                        'messaging flows cannot repeat a flow',
                                        'messaging templates cannot repeat a template')
  end

  it 'rejects a template without name or language and a purpose that is too long' do
    assign('inboxes' => [{
             'inbox_id' => inbox.id, 'enabled' => true, 'flows' => [],
             'templates' => [{ 'name' => '', 'language' => 'es', 'purpose' => 'x' * 301 }]
           }])

    expect(messaging_errors.join).to include('template name must be a text', 'purpose must be a text up to 300')
  end

  it 'rejects values that are not objects or lists' do
    assign('inboxes' => 'all')

    expect(messaging_errors).to include('messaging inboxes must be a list')
  end

  it 'keeps the paid templates switch separate from the messaging block' do
    assistant.config = assistant.config.merge('allow_paid_templates' => true)

    expect(assistant.allow_paid_templates?).to be(true)
    expect(messaging_errors).to be_empty
  end

  context 'with the variables of a template' do
    let(:channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                                message_templates: [{ 'name' => 'reserva', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
                                                      'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}' }] }])
    end

    def with_params(params)
      template = { 'name' => 'reserva', 'language' => 'es' }
      template['processed_params'] = params unless params.nil?
      assign('inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true, 'flows' => [], 'templates' => [template] }])
    end

    it 'accepts a template whose variables are all filled' do
      with_params('body' => { 'nombre' => '{{ contact.first_name }}' })

      expect(messaging_errors).to be_empty
    end

    it 'rejects a template with a variable left empty' do
      with_params('body' => { 'nombre' => ' ' })

      expect(messaging_errors.join).to include('variable body.nombre is empty')
    end

    it 'rejects a text that is not valid Liquid' do
      with_params('body' => { 'nombre' => '{{ contact.name ' })

      expect(messaging_errors.join).to include('is not valid Liquid')
    end

    it 'allows a template that is still being set up, without variables yet' do
      with_params(nil)

      expect(messaging_errors).to be_empty
    end
  end
end
