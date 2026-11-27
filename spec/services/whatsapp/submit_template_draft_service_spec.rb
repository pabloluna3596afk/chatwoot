require 'rails_helper'

RSpec.describe Whatsapp::SubmitTemplateDraftService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:draft) { create(:whatsapp_template_draft, account: account) }

  it 'requeues a failed local submission for the same revision' do
    submission = draft.submissions.create!(account: account, actor: actor, revision: draft.lock_version, waba_id: 'waba-1',
                                           name: draft.name, language: draft.language, snapshot: { payload: {} },
                                           payload_digest: 'digest', status: 'failed', error_details: { code: 'submission_failed' })

    expect do
      described_class.new(draft, actor, draft.lock_version).perform
    end.to have_enqueued_job(Whatsapp::SubmitTemplateDraftJob).with(submission.id)

    expect(submission.reload).to have_attributes(status: 'submitting', error_details: {})
  end

  it 'does not requeue a submission that is already in progress' do
    submission = draft.submissions.create!(account: account, actor: actor, revision: draft.lock_version, waba_id: 'waba-1',
                                           name: draft.name, language: draft.language, snapshot: { payload: {} },
                                           payload_digest: 'digest', status: 'submitting')

    expect do
      described_class.new(draft, actor, draft.lock_version).perform
    end.not_to have_enqueued_job(Whatsapp::SubmitTemplateDraftJob)
    expect(submission.reload.status).to eq('submitting')
  end
end
