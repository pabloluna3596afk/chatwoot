require 'rails_helper'

RSpec.describe 'Captain inbox assignment payload', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Ventas') }
  let(:inbox) { create(:inbox, account: account) }

  it 'exposes the connected assistant and leaves unconnected inboxes null' do
    account.enable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    other_inbox = create(:inbox, account: account)

    get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.find { |item| item['id'] == inbox.id }['captain_assistant']).to eq('id' => assistant.id, 'name' => 'Ventas')
    expect(payload.find { |item| item['id'] == other_inbox.id }['captain_assistant']).to be_nil
  end

  it 'omits the assistant field when Captain is disabled' do
    account.disable_features!('captain_integration')
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)

    get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token

    expect(response.parsed_body['payload'].first).not_to have_key('captain_assistant')
  end

  it 'does not expose inboxes outside the requesting account' do
    account.enable_features!('captain_integration')
    other = create(:inbox)
    inbox

    get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token

    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(inbox.id)
    expect(response.parsed_body['payload'].pluck('id')).not_to include(other.id)
  end

  it 'preloads connected assistants in a bounded number of queries' do
    account.enable_features!('captain_integration')
    3.times { create(:captain_inbox, inbox: create(:inbox, account: account), captain_assistant: assistant) }
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, data|
      queries << data[:sql] if data[:sql].include?('FROM "captain_assistants"')
    end

    get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(queries.length).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'invalidates inbox cache on connecting, renaming and disconnecting an assistant' do
    inbox
    expect(account).to receive(:update_cache_key).with('inbox').exactly(3).times
    connection = create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    assistant.update!(name: 'Soporte')
    connection.destroy!
  end
end
