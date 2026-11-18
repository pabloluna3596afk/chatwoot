require 'rails_helper'

RSpec.describe Migration::CaptainMessagingMigrationReportJob do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:now) do
    Time.use_zone(Integrations::GoogleCalendar::Timezone.for(account)) { Time.zone.parse('2030-01-15 10:00:00') }
  end
  let(:templates) do
    [{ 'name' => 'cita_confirmacion', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}' }] },
     { 'name' => 'bienvenida', 'language' => 'es', 'category' => 'MARKETING', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates,
                              provider_config: { 'business_account_id' => '123' })
  end
  let(:messaging) do
    { 'inboxes' => [{ 'inbox_id' => channel.inbox.id, 'enabled' => true,
                      'templates' => [{ 'name' => 'cita_confirmacion', 'language' => 'es', 'purpose' => 'Confirmar',
                                        'processed_params' => { 'body' => { '1' => '{{ contact.name }}' } } },
                                      { 'name' => 'bienvenida', 'language' => 'es', 'purpose' => 'Saludar',
                                        'processed_params' => { 'body' => { '1' => '{{ contact.name }}' } } }] }] }
  end
  let(:assistant) { create(:captain_assistant, account: account, config: { 'messaging' => messaging }) }

  around { |example| travel_to(now) { example.run } }

  it 'stores an Aurora-like before/after report and exact backup without converting config' do
    original = assistant.config['messaging'].deep_dup

    described_class.perform_now

    expect(assistant.reload.config['messaging']).to eq(original)
    report = assistant.config_migration_report
    expect(report['backup']).to eq(original)
    expect(report.dig('inboxes', 0, 'after_preview', 'templates', 'marketing').first['name']).to eq('bienvenida')
    expect(report.dig('inboxes', 0, 'before', 'templates').last['processed_params']).to eq(
      'body' => { '1' => '{{ contact.name }}' }
    )
  end
end
