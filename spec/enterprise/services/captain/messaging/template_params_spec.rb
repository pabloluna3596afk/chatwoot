require 'rails_helper'

RSpec.describe Captain::Messaging::TemplateParams do
  let(:account) { create(:account) }
  let(:templates) do
    [{ 'name' => 'order_ready', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}' }] },
     { 'name' => 'order_ready', 'language' => 'en', 'category' => 'UTILITY', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hello {{correo}}' }] },
     { 'name' => 'order_date', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Date {{fecha}}' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates,
                              provider_config: { 'business_account_id' => '123' },
                              template_variable_bindings: { 'order_ready' => { 'nombre' => 'contact.name' } })
  end
  let(:inbox) { channel.inbox }
  let(:assistant) { create(:captain_assistant, account: account) }

  def configure_params(params)
    assistant.config = assistant.config.merge(
      'messaging' => {
        'version' => 2, 'revision' => 0,
        'inboxes' => [{ 'inbox_id' => inbox.id, 'enabled' => true, 'mode' => 'auto', 'params' => params }]
      }
    )
  end

  it 'does not fall through to a channel binding when an explicit override is invalid' do
    key = "#{channel.provider_config.fetch('business_account_id')}:order_ready|es"
    configure_params(key => { 'body' => { 'nombre' => '{{ appointment.date }}' } })
    template = templates.first

    _processed_params, missing = described_class.new(assistant, inbox, template).resolve

    expect(missing).to eq(['nombre'])
  end

  it 'does not use appointment aliases for a tool send' do
    configure_params({})

    _processed_params, missing = described_class.new(assistant, inbox, templates.last).resolve

    expect(missing).to eq(['fecha'])
  end

  it 'uses distinct WABA and language scoped overrides for language variants' do
    configure_params(
      "#{channel.provider_config.fetch('business_account_id')}:order_ready|es" => { 'body' => { 'nombre' => '{{ contact.name }}' } },
      "#{channel.provider_config.fetch('business_account_id')}:order_ready|en" => { 'body' => { 'correo' => '{{ contact.email }}' } }
    )

    spanish = described_class.new(assistant, inbox, templates[0]).resolve.first
    english = described_class.new(assistant, inbox, templates[1]).resolve.first

    expect(spanish.dig('body', 'nombre')).to eq('{{ contact.name }}')
    expect(english.dig('body', 'correo')).to eq('{{ contact.email }}')
  end

  it 'reports whether each resolved value comes from an override, inbox binding, or name alias' do
    key = "#{channel.provider_config.fetch('business_account_id')}:order_ready|es"
    configure_params(key => { 'body' => { 'nombre' => '{{ contact.first_name }}' } })

    _params, _missing, sources = described_class.new(assistant, inbox, templates.first).resolve

    expect(sources).to eq('body' => { 'nombre' => 'assistant' }, 'header' => {})
    configure_params({})
    _params, _missing, sources = described_class.new(assistant, inbox, templates.first).resolve
    expect(sources).to eq('body' => { 'nombre' => 'binding' }, 'header' => {})
    name_alias_template = templates.last.merge(
      'components' => [{ 'type' => 'BODY', 'text' => 'Hello {{correo}}' }]
    )
    _params, _missing, sources = described_class.new(assistant, inbox, name_alias_template).resolve
    expect(sources).to eq('body' => { 'correo' => 'alias' }, 'header' => {})
  end

  it 'resolves aliases alongside partial bindings and ignores stale binding keys' do
    configure_params({})
    channel.update!(template_variable_bindings: { 'order_ready' => { 'pedido' => 'conversation.id', 'old' => 'contact.email' } })
    template = templates.first.merge('components' => [{ 'type' => 'BODY', 'text' => '{{nombre}} {{pedido}}' }])

    params, missing, sources = described_class.new(assistant, inbox, template).resolve

    expect(params['body']).to eq('nombre' => '{{ contact.name }}', 'pedido' => '{{ conversation.id }}')
    expect(missing).to be_empty
    expect(sources['body']).to eq('nombre' => 'alias', 'pedido' => 'binding')
  end
end
