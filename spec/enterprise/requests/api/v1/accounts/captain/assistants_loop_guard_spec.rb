require 'rails_helper'

RSpec.describe 'Captain loop guard settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  it 'accepts optional integer settings without the V2 feature' do
    account.disable_features!('captain_integration_v2')
    patch url, params: { assistant: { config: { loop_guard_replies: 6, loop_guard_window_seconds: 120 } } },
               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(assistant.reload.config).to include('loop_guard_replies' => 6, 'loop_guard_window_seconds' => 120)
  end

  { loop_guard_replies: [nil, '4', 4.5, [], {}, 3, 21], loop_guard_window_seconds: [nil, '180', false, [], {}, 29, 301] }.each do |key, values|
    values.each do |value|
      it "rejects #{key}=#{value.inspect} atomically" do
        patch url, params: { assistant: { name: 'Not saved', config: { key => value } } },
                   headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assistant.reload.name).not_to eq('Not saved')
      end
    end
  end
end
