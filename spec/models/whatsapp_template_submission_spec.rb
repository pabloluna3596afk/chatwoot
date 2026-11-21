require 'rails_helper'

RSpec.describe WhatsappTemplateSubmission do
  let(:draft) { create(:whatsapp_template_draft) }
  let(:submission) do
    described_class.create!(whatsapp_template_draft: draft, account: draft.account, revision: 0, waba_id: 'waba', name: draft.name,
                            language: draft.language, snapshot: { 'body' => 'original' }, payload_digest: 'digest')
  end

  it 'keeps the submitted snapshot and identity immutable while preserving unknown remote states' do
    submission.update!(status: 'submitted', remote_id: '123', remote_status: 'NEW_META_STATE')
    expect(submission.reload.remote_status).to eq('NEW_META_STATE')
    submission.snapshot['body'] = 'changed'
    expect(submission).not_to be_valid
  end

  it 'has a database identity reservation shared across drafts and revisions' do
    submission
    other = submission.dup
    other.whatsapp_template_draft = create(:whatsapp_template_draft, account: draft.account)
    expect { other.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'retains the draft when it has submission history' do
    submission
    expect(draft.destroy).to be(false)
    expect(draft).to be_persisted
  end
end
