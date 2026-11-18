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
    configure_params('123:order_ready|es' => { 'body' => { 'nombre' => '{{ appointment.date }}' } })
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
      '123:order_ready|es' => { 'body' => { 'nombre' => '{{ contact.first_name }}' } },
      '123:order_ready|en' => { 'body' => { 'correo' => '{{ contact.email }}' } }
    )

    spanish = described_class.new(assistant, inbox, templates[0]).resolve.first
    english = described_class.new(assistant, inbox, templates[1]).resolve.first

    expect(spanish.dig('body', 'nombre')).to eq('{{ contact.first_name }}')
    expect(english.dig('body', 'correo')).to eq('{{ contact.email }}')
  end
end
