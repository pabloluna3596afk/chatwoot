require 'rails_helper'

RSpec.describe 'Captain task contracts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/tasks" }

  before do
    put_account_on_plan(account, captain_internal_calls: 1)
    account.enable_features!('captain_tasks')
  end

  it 'returns 429 with the service error code when the real internal allowance is exhausted' do
    account.current_usage_period.update!(internal_calls_consumed: 1)

    post "#{url}/rewrite", params: { content: 'Hello', operation: 'improve' }, headers: headers, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(JSON.parse(response.body)).to include('error_code' => 429)
    expect(account.reload.current_usage_period.internal_calls_consumed).to eq(1)
  end

  it 'rejects unsupported rewrite operations with 422 before invoking the service' do
    post "#{url}/rewrite", params: { content: 'Hello', operation: 'expand' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to include('error_code' => 422)
  end

  it 'returns 404 when the summarized conversation does not exist' do
    post "#{url}/summarize", params: { conversation_display_id: -1 }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)).to include('error_code' => 404)
  end

  it 'returns 403 when Captain tasks are disabled for the account' do
    account.disable_features!('captain_tasks')

    post "#{url}/rewrite", params: { content: 'Hello', operation: 'casual' }, headers: headers, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)).to include('error_code' => 403)
  end

  it 'preserves a missing-key error as 401' do
    allow_any_instance_of(Captain::RewriteService).to receive(:api_key_configured?).and_return(false)

    post "#{url}/rewrite", params: { content: 'Hello', operation: 'casual' }, headers: headers, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to include('error_code' => 401)
  end

  it 'returns 502 for a provider error without an error code' do
    rewrite_service = instance_double(Captain::RewriteService, perform: { error: 'provider failed' })
    allow(Captain::RewriteService).to receive(:new).and_return(rewrite_service)

    post "#{url}/rewrite", params: { content: 'Hello', operation: 'casual' }, headers: headers, as: :json

    expect(response).to have_http_status(:bad_gateway)
    expect(JSON.parse(response.body)).to include('error_code' => 502)
  end
end
