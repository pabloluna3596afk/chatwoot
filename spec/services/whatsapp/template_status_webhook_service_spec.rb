require 'rails_helper'

RSpec.describe Whatsapp::TemplateStatusWebhookService do
  let(:account) { create(:account, locale: 'es') }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:draft) do
    create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config.fetch('business_account_id'))
  end
  let!(:submission) do
    draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: 'es',
                              snapshot: { 'payload' => {} }, payload_digest: 'digest', status: 'submitted',
                              remote_id: 'meta-42', remote_status: 'PENDING')
  end
  let(:value) { { event: 'APPROVED', message_template_id: 'meta-42' } }
  let(:params) do
    { object: 'whatsapp_business_account', entry: [{ id: draft.waba_id, changes: [{ field: described_class::FIELD, value: value }] }] }
  end

  it 'processes APPROVED without resolving a phone channel and leaves the snapshot immutable' do
    job = Webhooks::WhatsappEventsJob.new
    expect(job).not_to receive(:find_channel_from_whatsapp_business_payload)
    expect(BackgroundTasks::Notifier).to receive(:publish).with(hash_including(
                                                                  status: 'success', id: "whatsapp_template_submission:#{submission.id}"
                                                                ))
    expect { job.perform(params) }.to have_enqueued_job(Whatsapp::SyncTemplateWabaJob).with(account.id, draft.waba_id)
    expect(submission.reload).to have_attributes(remote_status: 'APPROVED', snapshot: { 'payload' => {} }, payload_digest: 'digest')
  end

  %w[REJECTED DISABLED PAUSED FLAGGED].each do |remote_status|
    it "publishes #{remote_status} with the remote reason" do
      value.merge!(event: remote_status, reason: 'Incorrect category', message_template_category: 'MARKETING')
      expect(BackgroundTasks::Notifier).to receive(:publish).with(hash_including(status: 'error', detail: a_string_including('Incorrect category')))
      described_class.new(params).perform
      expect(submission.reload).to have_attributes(remote_status: remote_status, remote_reason: 'Incorrect category', remote_category: 'MARKETING')
    end
  end

  it 'publishes PENDING as running' do
    submission.update!(remote_status: 'PAUSED')
    value[:event] = 'PENDING'
    expect(BackgroundTasks::Notifier).to receive(:publish).with(hash_including(status: 'running'))
    described_class.new(params).perform
    expect(submission.reload.remote_status).to eq('PENDING')
  end

  it 'records the category when supplied alongside the status' do
    value[:category] = 'MARKETING'
    described_class.new(params).perform
    expect(submission.reload.remote_category).to eq('MARKETING')
  end

  it 'does not publish or sync a repeated webhook' do
    described_class.new(params).perform
    expect(BackgroundTasks::Notifier).not_to receive(:publish)
    expect(Whatsapp::SyncTemplateWabaJob).not_to receive(:perform_later)
    described_class.new(params).perform
  end

  it 'ignores a template that does not belong to a recorded submission' do
    value[:message_template_id] = 'external-template'
    expect(BackgroundTasks::Notifier).not_to receive(:publish)
    expect { described_class.new(params).perform }.not_to(change { submission.reload.remote_status })
  end

  it 'does not match the remote id in another WABA' do
    params[:entry].first[:id] = 'other-waba'
    expect(BackgroundTasks::Notifier).not_to receive(:publish)
    described_class.new(params).perform
    expect(submission.reload.remote_status).to eq('PENDING')
  end
end
