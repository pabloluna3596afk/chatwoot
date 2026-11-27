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

  before do
    channel
    channel.update!(provider_config: channel.provider_config.merge('business_account_id' => 'waba-1'))
  end

  it 'creates one destination draft, submits it through the existing service, and skips it on repeat' do
    source
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, user, revision|
      expect(user).to eq(actor)
      expect(revision).to eq(0)
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: draft.submissions.create!(account: account, actor: actor, revision: revision,
                                                         waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                         snapshot: { 'payload' => { 'language' => draft.language } },
                                                         payload_digest: 'digest', status: 'submitting'))
    end
    args = { account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1'] }

    expect(described_class.new(**args).perform[:submissions].size).to eq(1)
    result = described_class.new(**args).perform
    expect(result[:submissions]).to be_empty
    expect(result[:skipped]).to include(hash_including(reason: 'already_submitted'))
    destination = account.whatsapp_template_drafts.find_by!(name: source.name, waba_id: 'waba-1')
    expect(destination.source_draft).to eq(source)
    expect(destination.submissions.size).to eq(1)
  end

  it 'records a failed destination in Activity and continues with the other WABA' do
    source
    second_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                               validate_provider_config: false,
                                               provider_config: { 'business_account_id' => 'waba-2' }, message_templates: [])
    second_channel.update!(provider_config: second_channel.provider_config.merge('business_account_id' => 'waba-2'))
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, user, revision|
      raise 'queue unavailable' if draft.waba_id == 'waba-1'

      expect(user).to eq(actor)
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: draft.submissions.create!(account: account, actor: user, revision: revision,
                                                         waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                         snapshot: { 'payload' => { 'language' => draft.language } },
                                                         payload_digest: 'digest', status: 'submitting'))
    end

    submissions = described_class.new(account: account, actor: actor, functions: ['confirmation'],
                                      waba_ids: %w[waba-1 waba-2]).perform

    expect(submissions[:submissions].map(&:status)).to eq(%w[failed submitting])
    expect(submissions[:submissions].first.error_details).to include('code' => 'submission_failed')
    expect(submissions[:submissions].first.error_details.to_json).not_to include('queue unavailable')
    expect(submissions[:failed]).to include(hash_including(reason: 'submission_failed'))
    activity = Whatsapp::TemplateBackgroundTask.task_payload(submissions[:submissions].first)
    expect(activity[:detail]).to eq(I18n.t('background_tasks.whatsapp_template.errors.submission_failed', locale: 'es'))
    expect(activity.to_json).not_to include('queue unavailable')
  end

  it 'allows retrying a local failure' do
    source_draft = source
    source_draft.update!(waba_id: 'waba-1', preferred_channel: channel)
    failed = source_draft.submissions.create!(account: account, actor: actor, revision: source_draft.lock_version,
                                              waba_id: 'waba-1', name: source_draft.name, language: source_draft.language,
                                              snapshot: { 'payload' => { 'language' => source_draft.language } },
                                              payload_digest: 'digest', status: 'failed',
                                              error_details: { 'code' => 'submission_failed' })
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: begin
                        failed.update!(status: 'submitting', error_details: {})
                        failed
                      end)
    end

    result = described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1']).perform

    expect(result[:submissions].sole).to eq(failed)
    expect(result[:skipped]).to be_empty
    expect(failed.reload.error_details).to eq({})
  end

  it 'creates a new revision when explicitly retrying a rejected submission' do
    draft = source
    draft.update!(waba_id: 'waba-1', preferred_channel: channel)
    rejected = draft.submissions.create!(account: account, actor: actor, revision: draft.lock_version,
                                         waba_id: 'waba-1', name: draft.name, language: draft.language,
                                         snapshot: { 'payload' => { 'language' => draft.language } },
                                         payload_digest: 'digest', status: 'submitted', remote_status: 'REJECTED')
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |target_draft, user, revision|
      expect(revision).to eq(rejected.revision + 1)
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: target_draft.submissions.create!(account: account, actor: user, revision: revision,
                                                                waba_id: target_draft.waba_id, name: target_draft.name,
                                                                language: target_draft.language,
                                                                snapshot: { 'payload' => { 'language' => target_draft.language } },
                                                                payload_digest: 'new-digest', status: 'submitting'))
    end

    result = described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1']).perform

    expect(result[:submissions].sole.revision).to eq(rejected.revision + 1)
    expect(result[:skipped]).to be_empty
  end

  it 'does not resubmit an approved submission at the current revision' do
    draft = source
    draft.update!(waba_id: 'waba-1', preferred_channel: channel)
    draft.submissions.create!(account: account, actor: actor, revision: draft.lock_version, waba_id: 'waba-1',
                              name: draft.name, language: draft.language,
                              snapshot: { 'payload' => { 'language' => draft.language } },
                              payload_digest: 'digest', status: 'submitted', remote_status: 'APPROVED')

    result = described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1']).perform

    expect(result[:submissions]).to be_empty
    expect(result[:skipped]).to include(hash_including(reason: 'already_submitted'))
  end

  it 'skips a destination draft owned by a different source and clears remote identity on a copy' do
    source_draft = source
    existing = account.whatsapp_template_drafts.create!(name: source_draft.name, language: source_draft.language,
                                                        category: source_draft.category,
                                                        parameter_format: source_draft.parameter_format,
                                                        definition: source_draft.definition,
                                                        waba_id: 'waba-1', source_remote_id: 'remote-source')
    result = described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1']).perform

    expect(result[:skipped]).to include(hash_including(reason: 'name_taken'))
    expect(existing.source_remote_id).to eq('remote-source')
  end

  it 'recovers when another request creates the destination draft first' do
    source_draft = source
    existing = account.whatsapp_template_drafts.create!(name: source_draft.name, language: source_draft.language,
                                                        category: source_draft.category,
                                                        parameter_format: source_draft.parameter_format,
                                                        definition: source_draft.definition, waba_id: 'waba-1',
                                                        preferred_channel: channel, source_draft: source_draft)
    submitter = described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1'])
    allow(submitter).to receive(:destination_draft).and_raise(ActiveRecord::RecordNotUnique, 'duplicate identity')
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, user, revision|
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: draft.submissions.create!(account: account, actor: user, revision: revision,
                                                         waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                         snapshot: { 'payload' => { 'language' => draft.language } },
                                                         payload_digest: 'digest', status: 'submitting'))
    end

    result = submitter.perform

    expect(result[:submissions].sole.whatsapp_template_draft).to eq(existing)
    expect(result[:failed]).to be_empty
    expect(result[:skipped]).to be_empty
  end

  it 'does not copy a source remote id to another WABA' do
    source_draft = source
    source_draft.update!(source_remote_id: 'meta-source-id')
    allow(Whatsapp::SubmitTemplateDraftService).to receive(:new) do |draft, user, revision|
      instance_double(Whatsapp::SubmitTemplateDraftService,
                      perform: draft.submissions.create!(account: account, actor: user, revision: revision,
                                                         waba_id: draft.waba_id, name: draft.name, language: draft.language,
                                                         snapshot: { 'payload' => { 'language' => draft.language } },
                                                         payload_digest: 'digest', status: 'submitting'))
    end

    described_class.new(account: account, actor: actor, functions: ['confirmation'], waba_ids: ['waba-1']).perform

    destination = account.whatsapp_template_drafts.find_by!(name: source_draft.name, waba_id: 'waba-1')
    expect(destination.source_remote_id).to be_nil
  end
end
