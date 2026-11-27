require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::Status do
  let(:account) { create(:account, locale: 'es') }
  let(:service) { described_class.new(account: account) }
  let(:template) do
    { 'id' => 'legacy', 'name' => 'cita_confirmacion', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY' }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: [template])
  end

  it 'returns empty destinations and zero totals without Cloud channels' do
    expect(service.perform['results'].values).to all(include('destinations' => [], 'ready_destinations' => 0, 'total_destinations' => 0))
    expect(service.perform).to include('prepared_language' => nil, 'effective_language' => 'es', 'language_changed' => false)
    expect(account.calendar_template_resources).to be_empty
  end

  it 'counts an approved UTILITY legacy template without any draft as usable' do
    channel
    row = service.perform['results']['confirmation']
    expect(row).to include('ready_destinations' => 1, 'total_destinations' => 1, 'linked' => false, 'approved' => false, 'draft_exists' => false)
    expect(row['destinations'].sole).to include('state' => 'usable', 'via' => 'legacy_by_name', 'resource_id' => nil, 'draft_id' => nil)
    expect(account.calendar_template_resources).to be_empty
  end

  it 'groups two numbers in one WABA and keeps another WABA unavailable' do
    channel
    second = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                       message_templates: [template])
    second.update!(provider_config: channel.provider_config)
    third = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    third.update!(provider_config: third.provider_config.merge('business_account_id' => 'other-waba'), message_templates: [])
    row = service.perform['results']['confirmation']
    expect(row).to include('ready_destinations' => 1, 'total_destinations' => 2)
    expect(row['destinations'].first['channels']).to eq([
                                                          { 'id' => channel.id, 'name' => channel.inbox.name,
                                                            'phone_number' => channel.phone_number },
                                                          { 'id' => second.id, 'name' => second.inbox.name,
                                                            'phone_number' => second.phone_number }
                                                        ])
    expect(row['destinations'].last).to include('waba_id' => 'other-waba', 'state' => 'missing', 'via' => 'none')
  end

  it 'reports local drafts as not submitted and preserves every legacy result key' do
    channel.update!(message_templates: [])
    Calendar::TemplateDrafts::Provisioner.new(account: account).perform
    row = service.perform['results']['confirmation']
    keys = %w[status draft_id draft_exists archived resource_id resources linked submission_status remote_status submitted approved]
    expect(row.keys).to include(*keys)
    expect(row['destinations'].sole).to include('state' => 'not_submitted', 'reason' => 'draft_not_submitted')
  end

  it 'uses the effective language rather than the prepared language to determine availability' do
    Calendar::TemplateDrafts::Provisioner.new(account: account).perform
    channel
    account.update!(locale: 'en')
    row = service.perform['results']['confirmation']
    expect(row).to include('prepared_language' => 'es', 'effective_language' => 'en', 'language_changed' => true, 'ready_destinations' => 0)
    expect(row['destinations'].sole['state']).to eq('missing')
  end

  it 'diagnoses pending remote approval without inventing a local draft or link' do
    channel.update!(message_templates: [template.merge('status' => 'PENDING')])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include('state' => 'pending_approval', 'via' => 'none')
  end

  it 'does not treat a recategorized legacy template as usable' do
    channel.update!(message_templates: [template.merge('category' => 'MARKETING')])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include('state' => 'incompatible', 'reason' => 'category')
  end

  it 'reports the worst destination state as the function aggregate' do
    channel
    other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    other.update!(provider_config: other.provider_config.merge('business_account_id' => 'other-waba'))
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', waba_id: 'other-waba')
    draft.submissions.create!(account: account, revision: 0, waba_id: 'other-waba', name: draft.name, language: 'es',
                              snapshot: { 'payload' => {} }, payload_digest: 'digest', status: 'failed')

    expect(service.perform.dig('results', 'confirmation')).to include('aggregate_state' => 'submission_failed')
  end

  it 'reports a compatible approved draft as usable without an explicit link' do
    channel.update!(message_templates: [])
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', waba_id: channel.provider_config['business_account_id'])
    definition = Calendar::TemplateDefinitions.definition('confirmation', 'es')
    template = { 'id' => 'meta-approved', 'name' => draft.name, 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
                 'parameter_format' => 'NAMED', 'components' => [
                   { 'type' => 'BODY', 'text' => definition[:body] },
                   { 'type' => 'BUTTONS', 'buttons' => definition[:buttons].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
                 ] }
    submission = draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: 'es',
                                           snapshot: { 'name' => draft.name }, payload_digest: 'digest',
                                           status: 'submitted', remote_status: 'PENDING')
    expect(service.perform['results']['confirmation']['destinations'].sole).to include(
      'state' => 'pending_approval', 'draft_id' => draft.id,
      'submission' => include('id' => submission.id, 'status' => 'submitted', 'remote_status' => 'PENDING')
    )
    submission.update!(remote_status: 'APPROVED', remote_id: 'meta-approved')
    channel.update!(message_templates: [template])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include('state' => 'usable', 'reason' => nil)
  end

  it 'keeps an approved submission incompatible when its category changes' do
    channel.update!(message_templates: [])
    draft = create(:whatsapp_template_draft, account: account, name: 'cita_confirmacion', waba_id: channel.provider_config['business_account_id'])
    definition = Calendar::TemplateDefinitions.definition('confirmation', 'es')
    template = { 'id' => 'meta-approved', 'name' => draft.name, 'language' => 'es', 'status' => 'APPROVED', 'category' => 'MARKETING',
                 'parameter_format' => 'NAMED', 'components' => [
                   { 'type' => 'BODY', 'text' => definition[:body] },
                   { 'type' => 'BUTTONS', 'buttons' => definition[:buttons].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
                 ] }
    draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: 'es',
                              snapshot: { 'name' => draft.name }, payload_digest: 'digest', status: 'submitted',
                              remote_id: 'meta-approved', remote_status: 'APPROVED')
    channel.update!(message_templates: [template])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include('state' => 'incompatible', 'reason' => 'category')
  end

  it 'revalidates linked versions through the real resolver and blocks legacy fallback after a version change' do
    definition = Calendar::TemplateDefinitions.definition('confirmation', 'es')
    candidate = template.merge('name' => 'custom_confirmation', 'parameter_format' => 'NAMED', 'components' => [
                                 { 'type' => 'BODY', 'text' => definition[:body] },
                                 { 'type' => 'BUTTONS', 'buttons' => definition[:buttons].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
                               ])
    channel.update!(message_templates: [candidate])
    resource = Calendar::TemplateResources.new(account: account, function: 'confirmation', language: 'es', channel: channel)
                                          .link!(template_name: candidate['name'], remote_template_id: candidate['id'])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include('state' => 'usable', 'via' => 'linked')
    candidate['components'].first['text'] += ' Gracias.'
    channel.update!(message_templates: [candidate, template])
    expect(service.perform['results']['confirmation']['destinations'].sole).to include(
      'state' => 'incompatible', 'reason' => 'version_changed', 'resource_id' => resource.id, 'via' => 'none'
    )
    expect(resource.reload.status).to eq('incompatible')
  end

  it 'does not advertise a WABA as ready when a number cannot resolve the template from its mirror' do
    channel
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: [])
    expect(service.perform['results']['confirmation']).to include('ready_destinations' => 0, 'total_destinations' => 1)
  end
end
