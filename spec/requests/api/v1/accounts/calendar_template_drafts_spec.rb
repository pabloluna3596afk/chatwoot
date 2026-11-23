require 'rails_helper'

RSpec.describe 'Calendar template preparation API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/template_drafts" }

  it 'reads pending status without preparing, and prepares through POST' do
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['results'].values.pluck('status')).to eq(%w[pending pending pending])
    expect(account.reload.calendar_template_preparation).to be_nil
    post path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['language']).to eq('es')
    expect(response.parsed_body['results']['confirmation']).to include(
      'status' => 'created', 'draft_id' => an_instance_of(Integer), 'resource_id' => an_instance_of(Integer),
      'submitted' => false, 'approved' => false, 'linked' => false, 'draft_exists' => true, 'archived' => false
    )
    expect { post path, headers: admin.create_new_auth_token }.not_to change(WhatsappTemplateDraft, :count)
  end

  [:get, :post].each do |verb|
    it "rejects anonymous #{verb}" do
      public_send(verb, path)
      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.calendar_template_preparation).to be_nil
    end

    it "rejects an agent's #{verb}" do
      agent = create(:user, account: account, role: :agent)
      public_send(verb, path, headers: agent.create_new_auth_token)
      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.calendar_template_preparation).to be_nil
    end

    it "does not expose or change another account through #{verb}" do
      other_admin = create(:user, account: create(:account), role: :administrator)
      public_send(verb, path, headers: other_admin.create_new_auth_token)
      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.calendar_template_preparation).to be_nil
    end
  end
  it 'accepts an explicit preparation language and diagnoses its difference from the effective language' do
    post path, headers: admin.create_new_auth_token, params: { language: 'en' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('prepared_language' => 'en', 'effective_language' => 'es', 'language_changed' => true)
    expect(account.whatsapp_template_drafts.pluck(:language).uniq).to eq(['en'])
    post path, headers: admin.create_new_auth_token, params: { language: ['en'] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

end
