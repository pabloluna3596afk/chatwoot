require 'rails_helper'

RSpec.describe Captain::Messaging::AssistantPayload do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'batches resource lookups for ten connected inboxes' do
    10.times do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false, message_templates: [],
                                          provider_config: { 'business_account_id' => '123' })
      create(:captain_inbox, captain_assistant: assistant, inbox: channel.inbox)
    end
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
    end

    result = described_class.new(assistant).as_json

    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(result[:inboxes].size).to eq(10)
    expect(queries.size).to be < 25
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'includes resolved template parameters for the inbox preview' do
    processed_params = { 'body' => { 'nombre' => '{{ contact.name }}' } }
    channel = create(
      :channel_whatsapp,
      account: account,
      provider: 'whatsapp_cloud',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: { 'business_account_id' => '123' },
      message_templates: [
        {
          'name' => 'pedido_listo',
          'language' => 'es',
          'category' => 'UTILITY',
          'status' => 'APPROVED',
          'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}' }]
        }
      ]
    )
    assistant.update!(
      config: {
        'messaging' => {
          'version' => 2,
          'revision' => 0,
          'inboxes' => [
            {
              'inbox_id' => channel.inbox.id,
              'enabled' => true,
              'mode' => 'list',
              'flows' => [],
              'templates' => [
                {
                  'name' => 'pedido_listo',
                  'language' => 'es',
                  'purpose' => 'Avisar del pedido',
                  'processed_params' => processed_params
                }
              ]
            }
          ]
        }
      }
    )
    create(:captain_inbox, captain_assistant: assistant, inbox: channel.inbox)

    result = described_class.new(assistant).as_json
    resource = result.dig(:inboxes, 0, :resources).find do |item|
      item.dig(:resource, 'name') == 'pedido_listo'
    end

    expect(resource[:state]).to eq('available')
    expect(resource[:processed_params]).to eq(processed_params.merge('header' => {}))
    expect(resource[:sources]).to eq('body' => { 'nombre' => 'legacy' }, 'header' => {})
  end

  it 'omits marketing and authentication resources and counts even when the inbox is disabled' do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false, provider_config: { 'business_account_id' => '123' },
                                        message_templates: %w[UTILITY MARKETING AUTHENTICATION].map do |category|
                                          { 'name' => category.downcase, 'language' => 'es', 'category' => category,
                                            'status' => 'APPROVED', 'components' => [] }
                                        end)
    create(:captain_inbox, captain_assistant: assistant, inbox: channel.inbox)
    payload = described_class.new(assistant).as_json[:inboxes].first
    expect(payload[:resources].map { |item| item[:resource]['category'] }).to eq(['UTILITY'])
    expect(payload[:counts]['disabled']).to eq(1)
    expect(payload[:counts].values.sum).to eq(1)
  end
end
