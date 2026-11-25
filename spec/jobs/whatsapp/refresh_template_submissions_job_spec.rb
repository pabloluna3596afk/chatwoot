require 'rails_helper'

RSpec.describe Whatsapp::RefreshTemplateSubmissionsJob do
  let(:account) { create(:account) }
  let(:draft) { create(:whatsapp_template_draft, account: account, waba_id: 'waba') }
  let(:attributes) do
    { account: account, waba_id: draft.waba_id, name: draft.name, language: 'es', snapshot: { 'payload' => {} },
      payload_digest: 'digest', status: 'submitted', remote_id: 'meta', updated_at: 11.minutes.ago }
  end

  it 'refreshes only old submitted non-final states, including null, with a bounded eagerly loaded batch' do
    pending = draft.submissions.create!(**attributes, revision: 0, remote_status: 'PENDING')
    paused = draft.submissions.create!(**attributes, revision: 1, remote_status: 'PAUSED')
    unknown = draft.submissions.create!(**attributes, revision: 2)
    draft.submissions.create!(**attributes, revision: 3, remote_status: 'APPROVED')
    draft.submissions.create!(**attributes, revision: 4, remote_status: 'REJECTED')
    draft.submissions.create!(**attributes, revision: 5, status: 'failed')
    draft.submissions.create!(**attributes, revision: 6, updated_at: Time.current)
    stub_const('Whatsapp::RefreshTemplateSubmissionsJob::LIMIT', 2)
    seen = []
    allow(Whatsapp::TemplateSubmissionService).to receive(:new) do |submission|
      seen << submission.id
      expect(submission.association(:account)).to be_loaded
      expect(submission.association(:actor)).to be_loaded
      expect(submission.association(:whatsapp_template_draft)).to be_loaded
      expect(submission.account.association(:whatsapp_channels)).to be_loaded
      instance_double(Whatsapp::TemplateSubmissionService, perform: nil).tap do |service|
        expect(service).to receive(:perform).with(refresh: true)
      end
    end
    described_class.perform_now
    expect(seen).to eq([pending.id, paused.id])
    stub_const('Whatsapp::RefreshTemplateSubmissionsJob::LIMIT', 100)
    seen.clear
    pending.update!(updated_at: 11.minutes.ago)
    paused.update!(updated_at: 11.minutes.ago)
    described_class.perform_now
    expect(seen).to contain_exactly(pending.id, paused.id, unknown.id)
  end

  it 'rotates unchanged pending rows so the next batch can make progress' do
    first = draft.submissions.create!(**attributes, revision: 0, remote_status: 'PENDING')
    second = draft.submissions.create!(**attributes, revision: 1, remote_status: 'PENDING')
    stub_const('Whatsapp::RefreshTemplateSubmissionsJob::LIMIT', 1)
    service = instance_double(Whatsapp::TemplateSubmissionService, perform: nil)
    expect(Whatsapp::TemplateSubmissionService).to receive(:new).with(have_attributes(id: first.id)).ordered.and_return(service)
    expect(Whatsapp::TemplateSubmissionService).to receive(:new).with(have_attributes(id: second.id)).ordered.and_return(service)
    described_class.perform_now
    described_class.perform_now
  end
end
