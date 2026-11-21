require 'rails_helper'

RSpec.describe Whatsapp::TemplateSubmissionService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:waba_id) { channel.provider_config.fetch('business_account_id') }
  let(:draft) { create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: waba_id) }
  let(:submission) { Whatsapp::SubmitTemplateDraftService.new(draft, actor, draft.lock_version).perform }
  let(:endpoint) { "https://graph.facebook.com/v22.0/#{waba_id}/message_templates" }
  let(:remote) { submission.snapshot.fetch('payload').except('parameter_format').merge('id' => 'meta-1', 'status' => 'PENDING') }

  before do
    stub_request(:get, endpoint).with(query: hash_including('name' => draft.name)).to_return(
      status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  it 'persists the immutable attempt before HTTP and records actual returned status/category' do
    post = stub_request(:post, endpoint).to_return do
      expect(submission.reload.status).to eq('reconciling')
      expect(submission.request_payload).to be_present
      { status: 200, body: { id: 'meta-1', status: 'PENDING', category: 'MARKETING' }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
    described_class.new(submission).perform
    expect(submission.reload).to have_attributes(status: 'submitted', remote_id: 'meta-1', remote_status: 'PENDING', remote_category: 'MARKETING')
    expect(post).to have_been_requested.once
    expect(Whatsapp::SyncTemplateWabaJob).to have_been_enqueued.with(account.id, waba_id)
    expect(channel.reload.message_templates).not_to include(a_hash_including('name' => draft.name))
  end

  it 'returns the same attempt for double click, another admin, and duplicate worker delivery' do
    first = submission
    other_actor = create(:user, account: account, role: :administrator)
    second = Whatsapp::SubmitTemplateDraftService.new(draft.reload, other_actor, draft.lock_version).perform
    expect(second.id).to eq(first.id)
    post = stub_request(:post, endpoint).to_return(status: 200, body: remote.to_json, headers: { 'Content-Type' => 'application/json' })
    described_class.new(first).perform
    described_class.new(second).perform
    expect(post).to have_been_requested.once
    expect(draft.submissions.count).to eq(1)
  end

  it 'keeps content fixed when the draft is edited after queueing' do
    original = submission.snapshot.deep_dup
    draft.update!(definition: { 'body' => { 'text' => 'Una revisión diferente.' } })
    post = stub_request(:post, endpoint).with(body: hash_including('components' => original.dig('payload', 'components')))
                                        .to_return(status: 200, body: remote.to_json, headers: { 'Content-Type' => 'application/json' })
    described_class.new(submission).perform
    expect(post).to have_been_requested.once
    expect(submission.reload.snapshot).to eq(original)
  end

  it 'holds an exclusive database session lock throughout HTTP without wrapping the intent in that transaction' do
    post = stub_request(:post, endpoint).to_return do
      # Rails transactional fixtures share their pool connection across threads; use an actual second PG session.
      connection = PG.connect(ActiveRecord::Base.connection.raw_connection.conninfo_hash.compact_blank)
      begin
        key = "whatsapp_template_submission/#{submission.id}"
        acquired = connection.exec_params('SELECT pg_try_advisory_lock(hashtextextended($1, 0))', [key]).getvalue(0, 0)
        expect(acquired).to eq('f')
      ensure
        connection.close
      end
      { status: 200, body: remote.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    described_class.new(submission).perform
    expect(post).to have_been_requested.once
  end

  it 'requires correction after a definite Meta validation error and redacts echoed samples and credentials' do
    post = stub_request(:post, endpoint).to_return(status: 400, body: {
      error: { code: 100, message: "Rejected #{draft.definition.dig('body', 'text')} token #{channel.template_access_token}" }
    }.to_json, headers: { 'Content-Type' => 'application/json' })
    described_class.new(submission).perform
    expect(submission.reload.status).to eq('failed')
    expect(submission.error_details.to_json).to include('[REDACTED]')
    expect(submission.error_details.to_json).not_to include(channel.template_access_token, draft.definition.dig('body', 'text'))
    described_class.new(submission).perform
    expect(post).to have_been_requested.once
    expect(Whatsapp::SubmitTemplateDraftService.new(draft.reload, actor, 0).perform.id).to eq(submission.id)
  end

  it 'reconciles a timeout with a matching remote identity without another POST' do
    post = stub_request(:post, endpoint).to_timeout
    described_class.new(submission).perform
    expect(submission.reload.status).to eq('reconciling')
    stub_request(:get, endpoint).with(query: hash_including('name' => draft.name)).to_return(
      status: 200, body: { data: [remote] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    travel 31.seconds do
      described_class.new(submission).perform
    end
    expect(submission.reload.status).to eq('submitted')
    expect(post).to have_been_requested.once
  end

  it 'keeps an absent or different identity reconciling after timeout without retrying creation' do
    post = stub_request(:post, endpoint).to_timeout
    described_class.new(submission).perform
    travel 31.seconds do
      described_class.new(submission).perform
    end
    expect(submission.reload.status).to eq('reconciling')
    expect(submission.next_retry_at).to be_nil
    expect(post).to have_been_requested.once
    mismatched = remote.merge('components' => [{ type: 'BODY', text: 'Other content' }])
    stub_request(:get, endpoint).with(query: hash_including('name' => draft.name)).to_return(
      status: 200, body: { data: [mismatched] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    described_class.new(submission).perform
    expect(submission.reload.error_details['code']).to eq('ambiguous_remote_identity')
    expect(post).to have_been_requested.once
  end

  it 'never adopts or overwrites a preexisting homonym on the first attempt' do
    stub_request(:get, endpoint).with(query: hash_including('name' => draft.name)).to_return(
      status: 200, body: { data: [remote] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    described_class.new(submission).perform
    expect(submission.reload.status).to eq('failed')
    expect(submission.error_details['code']).to eq('remote_identity_exists')
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  [429, 500].each do |status|
    it "bounds #{status} retries with backoff and checks identity before every retry" do
      post = stub_request(:post, endpoint).to_return(status: status, body: { error: { code: 4, message: 'Busy' } }.to_json,
                                                     headers: { 'Content-Type' => 'application/json' })
      described_class.new(submission).perform
      expect(submission.reload.next_retry_at).to be > Time.current
      described_class.new(submission).perform
      expect(post).to have_been_requested.once
      travel 31.seconds do
        described_class.new(submission).perform
      end
      travel 3.minutes do
        described_class.new(submission).perform
      end
      expect(post).to have_been_requested.times(3)
      expect(submission.reload.next_retry_at).to be_nil
      described_class.new(submission).perform
      expect(post).to have_been_requested.times(3)
    end
  end

  it 'does not use credentials after the channel changes WABA' do
    submission
    channel.update!(provider_config: channel.provider_config.merge('business_account_id' => 'different'))
    described_class.new(submission).perform
    expect(submission.reload.status).to eq('failed')
    expect(submission.error_details['code']).to eq('destination_changed')
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it 'uploads the frozen local attachment with destination credentials and keeps the wire payload immutable' do
    draft.media.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png', content_type: 'image/png')
    draft.update!(definition: { 'header' => { 'format' => 'IMAGE' }, 'body' => { 'text' => 'Tu cita está confirmada.' } })
    attempt = submission
    upload = instance_double(Whatsapp::TemplateHeaderHandleService, upload!: 'destination-handle')
    allow(Whatsapp::TemplateHeaderHandleService).to receive(:new).with(channel).and_return(upload)
    draft.update!(media: nil)
    post = stub_request(:post, endpoint).with(body: hash_including('components' => [
                                                                     { 'type' => 'HEADER', 'format' => 'IMAGE',
                                                                       'example' => { 'header_handle' => ['destination-handle'] } },
                                                                     { 'type' => 'BODY', 'text' => 'Tu cita está confirmada.' }
                                                                   ])).to_return(status: 200, body: remote.to_json,
                                                                                 headers: { 'Content-Type' => 'application/json' })
    described_class.new(attempt).perform
    expect(post).to have_been_requested.once
    expect(attempt.reload.media).to be_attached
    expect(attempt.snapshot.to_json).not_to include('destination-handle')
    attempt.request_payload = {}
    expect(attempt).not_to be_valid
  end

  it 'retains success when the subsequent WABA sync fails and can refresh unknown remote statuses' do
    stub_request(:post, endpoint).to_return(status: 200, body: remote.to_json, headers: { 'Content-Type' => 'application/json' })
    described_class.new(submission).perform
    sync = instance_double(Whatsapp::TemplateWabaSyncService)
    allow(sync).to receive(:perform).and_raise(Whatsapp::TemplateManagementService::Error, 'meta_unreachable')
    allow(Whatsapp::TemplateWabaSyncService).to receive(:new).with(account, waba_id).and_return(sync)
    Whatsapp::SyncTemplateWabaJob.perform_now(account.id, waba_id)
    expect(submission.reload.status).to eq('submitted')
    stub_request(:get, 'https://graph.facebook.com/v22.0/meta-1').with(query: hash_including('fields')).to_return(
      status: 200, body: remote.merge('status' => 'NEW_STATE', 'rejected_reason' => 'Remote reason').to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    described_class.new(submission).perform(refresh: true)
    expect(submission.reload).to have_attributes(status: 'submitted', remote_status: 'NEW_STATE', remote_reason: 'Remote reason')
  end
  context 'with a library draft' do
    let(:draft) do
      Whatsapp::TemplateDraftSourceService.new(account, actor, channel).from_library(
        library_template_name: 'appointment', name: 'my_appointment', language: 'es_EC', category: 'UTILITY',
        button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '+593999999999' }]
      )
    end
    let(:remote) do
      submission.snapshot.fetch('reconciliation_payload').merge('id' => 'meta-library', 'name' => draft.name, 'language' => 'es',
                                                               'status' => 'PENDING', 'category' => 'UTILITY')
    end

    before do
      stub_request(:get, 'https://graph.facebook.com/v22.0/message_template_library').with(query: hash_including('language' => 'es')).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ name: 'appointment', language: 'es', body: 'Tu cita', buttons: [{ type: 'PHONE_NUMBER', text: 'Llamar' }] }] }.to_json
      )
    end

    it 'sends the library wire payload through the existing Meta client rather than generic components' do
      post = stub_request(:post, endpoint).with(body: {
        name: 'my_appointment', language: 'es', category: 'UTILITY', library_template_name: 'appointment',
        library_template_button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '+593999999999' }]
      }.to_json).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: remote.to_json)
      described_class.new(submission).perform
      described_class.new(submission).perform
      expect(post).to have_been_requested.once
      expect(submission.reload).to have_attributes(status: 'submitted', language: 'es', remote_id: 'meta-library')
    end

    it 'matches the canonical remote language and content after a library POST timeout without repeating it' do
      post = stub_request(:post, endpoint).to_timeout
      described_class.new(submission).perform
      stub_request(:get, endpoint).with(query: hash_including('name' => draft.name)).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [remote] }.to_json
      )
      travel 31.seconds do
        described_class.new(submission).perform
      end
      expect(submission.reload.status).to eq('submitted')
      expect(post).to have_been_requested.once
    end
  end

end
