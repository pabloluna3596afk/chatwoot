require 'rails_helper'

RSpec.describe 'Background tasks API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:draft) do
    create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config.fetch('business_account_id'))
  end
  let(:attributes) do
    { account: account, waba_id: draft.waba_id, language: 'es', snapshot: { 'payload' => {} }, payload_digest: 'digest' }
  end
  let(:path) { "/api/v1/accounts/#{account.id}/background_tasks" }

  it 'returns active tasks and recent results for every account agent' do
    pending = draft.submissions.create!(**attributes, actor: agent, name: 'pending', revision: 0, status: 'submitted', remote_status: 'PENDING')
    submitting = draft.submissions.create!(**attributes, name: 'sending', revision: 1, status: 'submitting')
    reconciling = draft.submissions.create!(**attributes, name: 'reconciling', revision: 2, status: 'reconciling')
    draft.submissions.create!(**attributes, name: 'approved', revision: 3, status: 'submitted', remote_status: 'APPROVED')
    draft.submissions.create!(**attributes, name: 'rejected', revision: 4, status: 'submitted', remote_status: 'REJECTED')
    draft.submissions.create!(**attributes, name: 'failed', revision: 5, status: 'failed')
    draft.submissions.create!(**attributes, name: 'paused', revision: 6, status: 'submitted', remote_status: 'PAUSED')
    other_draft = create(:whatsapp_template_draft)
    other_draft.submissions.create!(account: other_draft.account, waba_id: 'other-waba', name: 'other', language: 'es', revision: 0,
                                    snapshot: { 'payload' => {} }, payload_digest: 'digest')
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expected = [pending, submitting, reconciling, draft.submissions.find_by!(name: 'approved'),
                draft.submissions.find_by!(name: 'rejected'), draft.submissions.find_by!(name: 'failed'),
                draft.submissions.find_by!(name: 'paused')]
               .map { |submission| Whatsapp::TemplateBackgroundTask.task_payload(submission).deep_stringify_keys }
    expect(response.parsed_body).to match_array(expected)
    expect(response.parsed_body.first.keys).to contain_exactly('id', 'kind', 'title', 'status', 'phase', 'version', 'updated_at', 'detail', 'link')
    expect(response.parsed_body.find { |task| task['id'] == "whatsapp_template_submission:#{pending.id}" }['phase']).to eq('waiting')
  end

  it 'allows agents because live updates are broadcast to all account agents' do
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  it 'rejects an administrator outside the account and unauthenticated requests' do
    outsider = create(:user, account: create(:account), role: :administrator)
    get path, headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it 'limits the query and preloads associations without per-task selects' do
    3.times do |revision|
      draft.submissions.create!(**attributes, name: "pending_#{revision}", revision: revision, status: 'submitted', remote_status: 'PENDING')
    end
    stub_const('BackgroundTasks::Sources::LIMIT', 2)
    headers = admin.create_new_auth_token
    allow(Whatsapp::TemplateBackgroundTask).to receive(:task_payload).and_wrap_original do |method, submission|
      expect(submission.association(:account)).to be_loaded
      method.call(submission)
    end
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      get path, headers: headers
    end
    expect(response.parsed_body.length).to eq(3)
    expect(queries.grep(/SELECT.*FROM "whatsapp_template_submissions"/)).to have_attributes(length: 2)
    expect(queries.grep(/SELECT.*FROM "whatsapp_template_drafts"/)).to be_empty
  end
end
