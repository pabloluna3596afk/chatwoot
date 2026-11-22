require 'rails_helper'

RSpec.describe Calendar::TemplateResources do
  let(:account) { create(:account, locale: 'es') }
  let(:template) do
    { 'id' => 'remote-1', 'name' => 'confirmacion_v2', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, cita {{cita}} el {{fecha}} a las {{hora}}.' },
        { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } } }
      ] }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'business_account_id' => 'waba-1' }, message_templates: [template])
  end
  let(:service) { described_class.new(account: account, function: :confirmation, language: 'es', channel: channel) }
  let(:binding) { service.link!(template_name: template['name'], remote_template_id: template['id']) }

  it 'requires an explicit link, never adopting a compatible template by a similar name' do
    expect(service.resolve).to be_nil
    expect(account.calendar_template_resources).to be_empty
    expect(binding).to have_attributes(status: 'linked', template_name: 'confirmacion_v2', remote_template_id: 'remote-1')
    expect(service.resolve).to eq(template)
    expect(binding.contract_snapshot).to include('variables' => %w[nombre cita fecha hora],
                                               'actions' => { 'Confirmar' => 'confirm', 'Reagendar' => 'reschedule', 'Cancelar' => 'cancel' })
  end

  it 'keeps repeated preparation idempotent and preserves a previously linked version' do
    binding
    expect { 2.times { service.prepare! } }.not_to change(CalendarTemplateResource, :count)
    expect(binding.reload.template_name).to eq('confirmacion_v2')
  end

  it 'captures the approved draft revision without following later local edits' do
    draft = create(:whatsapp_template_draft, account: account, waba_id: channel.provider_config['business_account_id'])
    record = service.link!(template_name: template['name'], remote_template_id: template['id'], draft: draft)
    draft.update!(title: 'Edited locally')
    expect(record.reload.contract_snapshot['draft_revision_at_link']).to eq(0)
    expect(service.resolve).to eq(template)
  end

  { 'category' => 'MARKETING', 'status' => 'PENDING', 'parameter_format' => 'POSITIONAL' }.each do |field, value|
    it "records an incompatible #{field} instead of linking by name" do
      channel.update!(message_templates: [template.merge(field => value)])
      expect(binding).to have_attributes(status: 'incompatible', incompatibility_reason: field, linked_at: nil)
      expect(service.resolve).to be_nil
    end
  end

  it 'rejects variables outside the selected appointment contract' do
    template['components'].first['text'] += ' {{email}}'
    expect(binding).to have_attributes(status: 'incompatible', incompatibility_reason: 'variables')
  end

  it 'rejects missing actions, reordered actions and non-quick-reply buttons' do
    template['components'].last['buttons'].reverse!
    expect(binding.incompatibility_reason).to eq('buttons')
    template['components'].last['buttons'] = []
    channel.update!(message_templates: [template])
    expect(service.link!(template_name: template['name'], remote_template_id: template['id']).incompatibility_reason).to eq('buttons')
  end

  it 'does not let a homonym with a different remote identity replace the chosen version' do
    binding
    channel.update!(message_templates: [template.merge('id' => 'remote-other')])
    expect(service.resolve).to be_nil
    expect(binding.reload.incompatibility_reason).to eq('missing_template')
  end

  it 'blocks a category change and does not fall back to an installed legacy template' do
    binding
    legacy = template.merge('name' => 'cita_confirmacion', 'id' => 'legacy')
    channel.update!(message_templates: [template.merge('category' => 'MARKETING'), legacy])
    expect(service.resolve).to be_nil
    expect(binding.reload).to have_attributes(status: 'incompatible', incompatibility_reason: 'category')
  end

  it 'requires an explicit relink after the approved content changes' do
    binding
    changed = template.deep_dup
    changed['components'].first['text'] += ' Gracias.'
    channel.update!(message_templates: [changed])
    expect(service.resolve).to be_nil
    expect(binding.reload.incompatibility_reason).to eq('version_changed')
    service.link!(template_name: template['name'], remote_template_id: template['id'])
    expect(service.resolve).to eq(changed)
  end

  it 'shares an identity between two numbers of the same WABA, never across WABAs' do
    binding
    second = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                      provider_config: channel.provider_config, message_templates: [template])
    resolver = described_class.new(account: account, function: :confirmation, language: 'es', channel: second)
    expect(resolver.resolve).to eq(template)
    expect(resolver.resource.id).to eq(binding.id)
    second.update!(provider_config: second.provider_config.merge('business_account_id' => 'other-waba'))
    expect(described_class.new(account: account, function: :confirmation, language: 'es', channel: second).resolve).to be_nil
  end

  it 'prepares once without a WABA and cannot link until a destination exists' do
    local = described_class.new(account: account, function: :confirmation, language: 'es')
    expect { 2.times { local.prepare! } }.to change(CalendarTemplateResource, :count).by(1)
    expect(local.resource.waba_id).to be_nil
    expect { local.link!(template_name: template['name'], remote_template_id: template['id']) }.to raise_error(ArgumentError)
  end

  it 'reuses the winning resource after a unique-index race in a fresh transaction' do
    winner = service.prepare!
    calls = 0
    allow(account).to receive(:with_lock).and_wrap_original do |original, **options, &block|
      calls += 1
      raise ActiveRecord::RecordNotUnique if calls == 1

      original.call(**options, &block)
    end
    expect(service.prepare!.id).to eq(winner.id)
    expect(calls).to eq(2)
  end

  it 'supports only approved UTILITY legacy templates when no resource exists' do
    channel.update!(message_templates: [template.merge('name' => 'cita_confirmacion')])
    expect(service.resolve['name']).to eq('cita_confirmacion')
    channel.update!(message_templates: [template.merge('name' => 'cita_confirmacion', 'category' => 'MARKETING')])
    expect(service.resolve).to be_nil
  end

  it 'preserves installed legacy uses while an identity is only pending preparation' do
    channel.update!(message_templates: [template.merge('name' => 'cita_confirmacion')])
    service.prepare!
    expect(service.resolve['name']).to eq('cita_confirmacion')
    expect(service.message_snapshot(service.resolve)).to include('resource_id' => nil, 'actions' => {
      'Confirmar' => 'confirm', 'Reagendar' => 'reschedule', 'Cancelar' => 'cancel'
    })
    expect(service.resource.reload.status).to eq('pending')
  end

  %w[cancellation reminder].each do |function|
    it "validates the #{function} contract independently" do
      definition = Calendar::TemplateDefinitions.definition(function, 'es')
      candidate = template.deep_dup
      candidate['name'] = "#{function}_v2"
      candidate['components'].last['buttons'] = definition[:buttons].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } }
      channel.update!(message_templates: [candidate])
      resolver = described_class.new(account: account, function: function, language: 'es', channel: channel)
      expect(resolver.link!(template_name: candidate['name'], remote_template_id: candidate['id']).status).to eq('linked')
      expect(resolver.resolve).to eq(candidate)
    end
  end
end
