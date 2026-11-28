require 'rails_helper'

RSpec.describe 'Conversation auto-translate control', type: :request do
  let(:account) { create(:account, auto_translate: true, translation_provider: 'captain') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, additional_attributes: { 'conversation_language' => 'fr' }) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}" }

  before do
    account.enable_features!(:auto_translate, :captain_tasks)
    create(:inbox_member, user: agent, inbox: conversation.inbox)
  end

  it 'keeps the new control off by default and ignores the parameter' do
    expect(account.feature_enabled?('conversation_auto_translate')).to be(false)
    patch url, params: { auto_translate_disabled: true }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.reload.auto_translate_disabled).to be_nil
  end

  context 'when the account enables the control' do
    before { account.enable_features!(:conversation_auto_translate) }

    it 'lets an agent disable and re-enable translation without losing the language' do
      [true, false].each do |disabled|
        patch url, params: { auto_translate_disabled: disabled }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.auto_translate_disabled).to eq(disabled)
        expect(conversation.language).to eq('fr')
        expect(conversation.auto_translate_enabled?).to eq(!disabled)
      end
    end

    [nil, 'true', 'yes', 1, [], {}].each do |invalid|
      it "rejects #{invalid.inspect} at the request boundary" do
        patch url, params: { auto_translate_disabled: invalid }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(conversation.reload.auto_translate_disabled).to be_nil
      end
    end

    it 'rejects translation requests while disabled in this conversation' do
      conversation.update!(auto_translate_disabled: true)
      message = create(:message, conversation: conversation, message_type: :incoming, content: 'Bonjour')

      expect do
        post "#{url}/messages/auto_translate", params: { message_ids: [message.id] }, headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Captain::Conversation::ContactMessageTranslationJob)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
