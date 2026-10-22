require 'rails_helper'

RSpec.describe Calendar::ActivationKit do
  let(:account) { create(:account, locale: 'es') }
  let(:kit) { described_class.new(account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:service) { instance_double(Whatsapp::TemplateManagementService) }

  before do
    inbox
    allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(service)
    allow(Calendar::AppointmentAttributes::BackfillJob).to receive(:perform_later)
  end

  def stored_template(status, extra = {})
    template = { 'name' => described_class::TEMPLATE_NAME, 'language' => 'es', 'status' => status }.merge(extra)
    channel.update_column(:message_templates, [template]) # rubocop:disable Rails/SkipsModelValidations
  end

  describe '#status' do
    it 'lists the WhatsApp Cloud inboxes with the template missing' do
      expect(kit.status[:inboxes]).to eq([{ id: inbox.id, name: inbox.name, status: 'missing', rejected_reason: nil }])
    end

    it 'shows the status and rejection reason Meta synced' do
      stored_template('REJECTED', 'rejected_reason' => 'INVALID_FORMAT')

      expect(kit.status[:inboxes].first).to include(status: 'rejected', rejected_reason: 'INVALID_FORMAT')
    end

    it 'ignores inboxes that are not WhatsApp Cloud' do
      create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)

      expect(kit.status[:inboxes].pluck(:id)).to eq([inbox.id])
    end

    it 'falls back to Spanish for a language without a template' do
      account.update!(locale: 'fr')

      expect(kit.language).to eq('es')
    end
  end

  describe '#apply' do
    before { allow(service).to receive(:create).and_return(id: '1', status: 'PENDING') }

    it 'creates the attributes and sends the confirmation template to the chosen inbox' do
      result = kit.apply(inbox_ids: [inbox.id])

      expect(account.custom_attribute_definitions.contact_attribute.pluck(:attribute_key)).to match_array(
        Calendar::AppointmentAttributes::Definitions::TYPES.keys
      )
      expect(service).to have_received(:create).with(
        hash_including(name: 'cita_confirmacion', language: 'es', category: 'UTILITY', parameter_format: 'NAMED')
      )
      expect(result[:results]).to eq(inbox.id => { status: 'pending' })
    end

    it 'sends a body with named variables the catalog fills and quick-reply buttons' do
      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create) do |args|
        body = args[:components].find { |component| component[:type] == 'BODY' }
        buttons = args[:components].find { |component| component[:type] == 'BUTTONS' }
        expect(body[:text]).to include('{{nombre}}', '{{cita}}', '{{fecha}}', '{{hora}}')
        expect(buttons[:buttons].pluck(:type).uniq).to eq(['QUICK_REPLY'])
      end
    end

    it 'does not touch inboxes that were not chosen' do
      kit.apply(inbox_ids: [])

      expect(service).not_to have_received(:create)
    end

    it 'keeps the attributes the administrator already chose' do
      Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: %w[total_citas])

      kit.apply(inbox_ids: [])

      expect(account.reload.appointment_attributes['keys']).to eq(%w[total_citas])
    end

    it 'does not send again a template that is pending or approved' do
      stored_template('APPROVED')

      expect(kit.apply(inbox_ids: [inbox.id])[:results]).to eq(inbox.id => { status: 'approved' })
      expect(service).not_to have_received(:create)
    end

    it 'sends again a template Meta rejected' do
      stored_template('REJECTED')

      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create)
    end

    it 'reports the Meta error without raising' do
      allow(service).to receive(:create).and_raise(Whatsapp::TemplateManagementService::Error.new('permission_denied', detail: 'no access'))

      expect(kit.apply(inbox_ids: [inbox.id])[:results]).to eq(inbox.id => { status: 'error', code: 'permission_denied', detail: 'no access' })
    end
  end
end
