require 'rails_helper'

RSpec.describe 'Calendar template submission API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false,
                              provider_config: { 'business_account_id' => 'waba-1' }, message_templates: [])
  end
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/template_drafts/submit" }
  let(:params) { { functions: ['confirmation'], waba_ids: ['waba-1'] } }

  before do
    channel
    Calendar::TemplateDrafts::Provisioner.new(account: account).perform
  end

  it 'submits the selected appointment template to Meta through the existing background job' do
    expect { post path, headers: admin.create_new_auth_token, params: params, as: :json }
      .to have_enqueued_job(Whatsapp::SubmitTemplateDraftJob)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body['submissions'].sole).to include('status' => 'submitting', 'waba_id' => 'waba-1')
    expect(Message.count).to eq(0)
  end

  it 'rejects an agent and invalid function or destination selections' do
    agent = create(:user, account: account, role: :agent)
    post path, headers: agent.create_new_auth_token, params: params, as: :json
    expect(response).to have_http_status(:unauthorized)

    post path, headers: admin.create_new_auth_token, params: { functions: ['unknown'], waba_ids: ['waba-1'] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post path, headers: admin.create_new_auth_token, params: { functions: ['confirmation'], waba_ids: ['other'] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
