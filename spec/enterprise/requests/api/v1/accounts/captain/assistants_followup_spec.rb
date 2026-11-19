require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants follow-up settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  it 'returns the follow-up defaults and paid templates off' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(json_response[:config][:followup]).to eq(
      inactivity_enabled: true, inactivity_after_minutes: 10, max_nudges: 1, close_after_minutes: 120,
      reengagement_enabled: false, reengagement_template: nil
    )
    expect(json_response[:config][:allow_paid_templates]).to be(false)
  end

  it 'saves the follow-up settings and the one paid templates switch' do
    followup = { inactivity_enabled: false, inactivity_after_minutes: 45, max_nudges: 2, close_after_minutes: 240,
                 reengagement_enabled: true, reengagement_template: { name: 'volver', language: 'es' } }

    patch url, params: { assistant: { config: { followup: followup, allow_paid_templates: true } } },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:followup]).to eq(followup)
    expect(json_response[:config][:allow_paid_templates]).to be(true)
    expect(assistant.reload).to be_allow_paid_templates
  end

  it 'rejects invalid follow-up settings' do
    patch url, params: { assistant: { config: { followup: { max_nudges: 5 } } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'merges a follow-up-only patch without a messaging revision or overwriting closure settings' do
    assistant.update!(config: assistant.config.merge(
      'allow_paid_templates' => true, 'auto_resolve_after' => 120, 'messaging' => { 'version' => 2, 'revision' => 4, 'inboxes' => [] }
    ))
    messaging = assistant.config['messaging']

    patch url, params: { assistant: { config: { followup: { inactivity_enabled: false, inactivity_after_minutes: 30 } } } },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(assistant.reload).to be_allow_paid_templates
    expect(assistant.config).to include('messaging' => messaging, 'auto_resolve_after' => 120)
  end

  describe 'completion detection' do
    before { account.enable_features!('captain_integration_v2') }

    it 'saves explicit activation with one of the allowed grace periods' do
      patch url, params: { assistant: { config: { completion_signal_enabled: true, completion_grace_minutes: 10 } } },
                 headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(assistant.reload.config).to include('completion_signal_enabled' => true, 'completion_grace_minutes' => 10)
    end

    [{ completion_signal_enabled: {} }, { completion_signal_enabled: 'true' }, { completion_grace_minutes: [] },
     { completion_grace_minutes: '5' }, { completion_grace_minutes: 6 }].each do |config|
      it "rejects invalid input at the request boundary: #{config.inspect}" do
        patch url, params: { assistant: { config: config } }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
