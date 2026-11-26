require 'rails_helper'

RSpec.describe Calendar::TemplateDrafts::Submitter do
  let(:account) { create(:account, locale: 'es') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false,
                              provider_config: { 'business_account_id' => 'waba-1' }, message_templates: [])
  end
  let(:source) do
    Calendar::TemplateDrafts::Provisioner.new(account: account).perform
    account.whatsapp_template_drafts.find_by!(name: 'cita_confirmacion')
  end

  before { channel }

  it 'creates one destination draft, submits it through the existing service, and skips it on repeat' do
    source
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, user, revision|
      expect(user).to eq(actor)
      expect(revision).to eq(0)
      double(perform: draft.submissions.create!(account: account, actor: actor, revision: revision,
                                                waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                snapshot: { 'payload' => { 'language' => draft.language } },
                                                payload_digest: 'digest', status: 'submitting'))
    end
    args = { account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1'] }

    expect(described_class.new(**args).perform.size).to eq(1)
    expect(described_class.new(**args).perform).to be_empty
    destination = account.whatsapp_template_drafts.find_by!(name: source.name, waba_id: 'waba-1')
    expect(destination.source_draft).to eq(source)
    expect(destination.submissions.size).to eq(1)
  end

  it 'records a failed destination in Activity and continues with the other WABA' do
    source
    second_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                              validate_provider_config: false,
                                              provider_config: { 'business_account_id' => 'waba-2' }, message_templates: [])
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, actor, revision|
      raise 'queue unavailable' if draft.waba_id == 'waba-1'

      double(perform: draft.submissions.create!(account: account, actor: actor, revision: revision,
                                                waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                snapshot: { 'payload' => { 'language' => draft.language } },
                                                payload_digest: 'digest', status: 'submitting'))
    end

    submissions = described_class.new(account: account, actor: actor, functions: ['confirmation'],
                                       waba_ids: ['waba-1', 'waba-2']).perform

    expect(second_channel).to be_persisted
    expect(submissions.map(&:status)).to eq(%w[failed submitting])
    expect(submissions.first.error_details).to include('code' => 'submission_failed')
  end
end
