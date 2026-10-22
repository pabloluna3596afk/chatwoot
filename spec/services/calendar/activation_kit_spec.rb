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
      expect(kit.status[:inboxes]).to eq([{ id: inbox.id, name: inbox.name, status: 'missing', rejected_reason: nil,
                                            cancel_status: 'missing', cancel_rejected_reason: nil,
                                            reminder_status: 'missing', reminder_rejected_reason: nil }])
    end

    it 'shows the status and rejection reason Meta synced' do
      stored_template('REJECTED', 'rejected_reason' => 'INVALID_FORMAT')

      expect(kit.status[:inboxes].first).to include(status: 'rejected', rejected_reason: 'INVALID_FORMAT')
    end

    %w[es en].each do |locale|
      it "exposes all three template summaries in #{locale}" do
        account.update!(locale: locale)

        expect(kit.status[:reminder_template]).to include(name: 'cita_recordatorio', language: locale,
                                                        buttons: described_class::TEMPLATES[locale][:buttons])
        expect(kit.status[:reminder_enabled]).to be(false)
        expect(kit.status[:template]).to include(name: 'cita_confirmacion', language: locale, buttons: an_instance_of(Array))
        expect(kit.status[:cancel_template]).to eq(
          name: 'cita_cancelacion', language: locale, category: 'UTILITY', body: described_class::CANCEL_TEMPLATES[locale][:body]
        )
      end
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
      expect(result[:results]).to eq(inbox.id => { status: 'pending', cancel: { status: 'pending' }, reminder: { status: 'pending' } })
    end

    it 'sends a body with named variables the catalog fills and quick-reply buttons' do
      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create).with(hash_including(name: 'cita_confirmacion')) do |args|
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

      result = kit.apply(inbox_ids: [inbox.id])[:results]
      expect(result).to eq(inbox.id => { status: 'approved', cancel: { status: 'pending' }, reminder: { status: 'pending' } })
      expect(service).not_to have_received(:create).with(hash_including(name: 'cita_confirmacion'))
    end

    it 'sends again a template Meta rejected' do
      stored_template('REJECTED')

      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create).exactly(3).times
    end

    it 'reports the Meta error without raising' do
      allow(service).to receive(:create).and_raise(Whatsapp::TemplateManagementService::Error.new('permission_denied', detail: 'no access'))

      failure = { status: 'error', code: 'permission_denied', detail: 'no access' }
      expect(kit.apply(inbox_ids: [inbox.id])[:results]).to eq(inbox.id => failure.merge(cancel: failure, reminder: failure))
    end

    %w[es en].each do |locale|
      it "submits reminder in #{locale} with the same button text and order as confirmation" do
        account.update!(locale: locale)
        kit.apply(inbox_ids: [inbox.id])
        expect(service).to have_received(:create).with(hash_including(name: 'cita_recordatorio', language: locale)) do |args|
          expect(args[:components].first[:text]).to include('{{nombre}}', '{{cita}}', '{{fecha}}', '{{hora}}')
          expect(args[:components].last[:buttons].pluck(:text)).to eq(described_class::TEMPLATES[locale][:buttons])
        end
      end
    end

    it 'submits cancellation without buttons and with named variables' do
      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create).with(hash_including(name: 'cita_cancelacion')) do |args|
        expect(args[:components].pluck(:type)).to eq(['BODY'])
        expect(args[:components].first[:text]).to include('{{nombre}}', '{{cita}}', '{{fecha}}', '{{hora}}')
      end
    end

    %w[PENDING APPROVED IN_APPEAL].each do |state|
      it "reuses both templates in #{state}" do
        templates = described_class::DEFINITIONS.keys.map do |name|
          { 'name' => name, 'language' => 'es', 'status' => state }
        end
        channel.update!(message_templates: templates)

        kit.apply(inbox_ids: [inbox.id])

        expect(service).not_to have_received(:create)
      end
    end

    it 'resends only the rejected cancellation template' do
      channel.update!(message_templates: [
                        { 'name' => 'cita_confirmacion', 'language' => 'es', 'status' => 'APPROVED' },
                        { 'name' => 'cita_recordatorio', 'language' => 'es', 'status' => 'APPROVED' },
                        { 'name' => 'cita_cancelacion', 'language' => 'es', 'status' => 'REJECTED', 'rejected_reason' => 'INVALID_FORMAT' }
                      ])
      expect(kit.status[:inboxes].first).to include(cancel_status: 'rejected', cancel_rejected_reason: 'INVALID_FORMAT')

      kit.apply(inbox_ids: [inbox.id])

      expect(service).to have_received(:create).with(hash_including(name: 'cita_cancelacion')).once
      expect(service).not_to have_received(:create).with(hash_including(name: 'cita_confirmacion'))
    end

    %w[cita_confirmacion cita_cancelacion cita_recordatorio].each do |failed_name|
      it "still sends the other template when #{failed_name} fails" do
        allow(service).to receive(:create).with(hash_including(name: failed_name))
                                          .and_raise(Whatsapp::TemplateManagementService::Error.new('permission_denied'))

        result = kit.apply(inbox_ids: [inbox.id])[:results][inbox.id]

        expect(service).to have_received(:create).exactly(3).times
        expect([result[:status], result[:cancel][:status], result[:reminder][:status]]).to match_array(%w[error pending pending])
      end
    end
  end
end
