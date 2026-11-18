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
  let(:assistant) do
    create(:captain_assistant, account: account, config: { 'messaging' => messaging, 'allow_paid_templates' => true })
  end

  around { |example| travel_to(now) { example.run } }

  it 'stores an exact backup and machine-readable before/after report without converting config' do
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

  it 'stores the Aurora-like compact summary with names and migration differences' do
    assistant
    described_class.perform_now
    summary = assistant.reload.config_migration_report.dig('inboxes', 0, 'summary')
    expect(summary.dig('before', 'templates')).to contain_exactly(
      { 'name' => 'cita_confirmacion (es)', 'category' => 'UTILITY', 'purpose_present' => true, 'params_present' => true },
      { 'name' => 'bienvenida (es)', 'category' => 'MARKETING', 'purpose_present' => true, 'params_present' => true }
    )
    expect(summary.dig('after_auto_would_allow', 'available')).to eq(['cita_confirmacion (es)'])
    expect(summary.dig('after_auto_would_allow', 'new')).to eq(['bienvenida (es)'])
    expect(summary.dig('differences', 'lost')).to eq(['bienvenida (es)'])
  end

  it 'prints the Aurora-like summary in Spanish plain text' do
    assistant
    described_class.perform_now
    report = assistant.reload.config_migration_report
    expected_text = [
      "Bandeja: #{channel.inbox.name} (##{channel.inbox.id})",
      'Hoy puede enviar: cita_confirmacion (es), bienvenida (es)',
      'Con el modo automático podría enviar: cita_confirmacion (es)',
      'Ganaría: (ninguno)',
      'Perdería: bienvenida (es)',
      'Necesita revisión: bienvenida (es)'
    ].join("\n")
    expect(Captain::Messaging::MigrationReportText.new(report).render).to eq(expected_text)
  end

  it 'is idempotent and never converts config.messaging' do
    original = assistant.config['messaging'].deep_dup
    described_class.perform_now
    report = assistant.reload.config_migration_report
    described_class.perform_now
    expect(assistant.reload.config['messaging']).to eq(original)
    expect(assistant.reload.config_migration_report).to eq(report)
  end

  it 'adds the compact summary to a report saved by round 2 and keeps its backup' do
    original = assistant.config['messaging'].deep_dup
    assistant.update!(config_migration_report: { 'backup' => original, 'inboxes' => [{ 'inbox_id' => channel.inbox.id }] })

    described_class.perform_now(assistant.id)

    expect(assistant.reload.config_migration_report['backup']).to eq(original)
    expect(assistant.config_migration_report.dig('inboxes', 0, 'summary')).to be_present
  end

  it 'reports a Cloud inbox without WABA id without raising or changing messaging config' do
    channel.update!(provider_config: { 'api_key' => 'token' })
    original = assistant.config['messaging'].deep_dup

    expect { described_class.perform_now(assistant.id) }.not_to raise_error
    expect(assistant.reload.config['messaging']).to eq(original)
    expect(assistant.config_migration_report.dig('inboxes', 0, 'summary')).to be_present
  end
end
