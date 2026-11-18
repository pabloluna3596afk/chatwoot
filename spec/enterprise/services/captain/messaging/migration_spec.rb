require 'rails_helper'

RSpec.describe Captain::Messaging::Migration do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:now) do
    Time.use_zone(Integrations::GoogleCalendar::Timezone.for(account)) { Time.zone.parse('2030-01-15 10:00:00') }
  end
  let(:template) do
    { 'name' => 'promo', 'language' => 'es', 'category' => 'MARKETING', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}' }] }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: [template],
                              provider_config: { 'business_account_id' => '123' })
  end
  let(:original) do
    {
      'inboxes' => [
        {
          'inbox_id' => channel.inbox.id,
          'enabled' => true,
          'templates' => [
            {
              'name' => 'promo',
              'language' => 'es',
              'purpose' => 'Saludo',
              'processed_params' => { 'body' => { '1' => '{{ contact.name }}' } }
            }
          ]
        }
      ]
    }
  end
  let(:assistant) do
    create(:captain_assistant, account: account, config: { 'messaging' => original },
                               config_migration_report: { 'backup' => original })
  end

  around { |example| travel_to(now) { example.run } }

  it 'converts only on request and restores the exact saved messaging block' do
    described_class.convert!(assistant)
    converted = assistant.reload.config.dig('messaging', 'inboxes', 0)
    expect(converted['mode']).to eq('auto')
    expect(converted['included_marketing']).to eq(['123:promo|es'])
    expect(converted.dig('params', '123:promo|es')).to eq('body' => { '1' => '{{ contact.name }}' })
    first_conversion = assistant.reload.config['messaging']
    described_class.convert!(assistant)
    expect(assistant.reload.config['messaging']).to eq(first_conversion)

    described_class.restore!(assistant)
    described_class.restore!(assistant)

    expect(assistant.reload.config['messaging']).to eq(original)
  end
end
