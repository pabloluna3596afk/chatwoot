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

  before { Migration::CaptainMessagingMigrationReportJob.perform_now(assistant.id) }

  it 'refuses a report after the template catalog changes' do
    channel.update!(message_templates: [template.merge('category' => 'UTILITY')])
    expect { described_class.convert!(assistant) }.to raise_error do |error|
      expect(error.class.name).to eq('Captain::Messaging::Migration::StaleReport')
      expect(error.message).to eq('el reporte está desactualizado: genera uno nuevo')
    end
    expect(assistant.reload.config['messaging']).to eq(original)
  end

  it 'requires a new report after configuration changes and restores exactly that configuration' do
    assistant.update!(config: assistant.config.merge('product_name' => 'Updated'))
    expect { described_class.convert!(assistant) }.to raise_error do |error|
      expect(error.class.name).to eq('Captain::Messaging::Migration::StaleReport')
    end
    Migration::CaptainMessagingMigrationReportJob.perform_now(assistant.id)
    previous = assistant.reload.config.deep_dup
    described_class.convert!(assistant)
    described_class.restore!(assistant)
    expect(assistant.reload.config).to eq(previous)
  end

  it 'refuses a report after a Flow is added' do
    create(:whatsapp_flow, account: account)
    expect { described_class.convert!(assistant) }.to raise_error do |error|
      expect(error.class.name).to eq('Captain::Messaging::Migration::StaleReport')
    end
  end

  it 'converts only on request and restores the exact saved messaging block' do
    described_class.convert!(assistant)
    converted = assistant.reload.config.dig('messaging', 'inboxes', 0)
    expect(converted['mode']).to eq('auto')
    key = "#{channel.provider_config.fetch('business_account_id')}:promo|es"
    expect(converted['included_marketing']).to eq([])
    expect(converted.dig('notes', "template:#{key}")).to eq('Saludo')
    expect(converted.dig('params', key)).to eq('body' => { '1' => '{{ contact.name }}' })
    first_conversion = assistant.reload.config['messaging']
    described_class.convert!(assistant)
    expect(assistant.reload.config['messaging']).to eq(first_conversion)

    described_class.restore!(assistant)
    described_class.restore!(assistant)

    expect(assistant.reload.config['messaging']).to eq(original)
  end
end
