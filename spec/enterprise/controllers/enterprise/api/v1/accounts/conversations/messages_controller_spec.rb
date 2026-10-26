require 'rails_helper'

RSpec.describe 'Enterprise Conversation Messages API', type: :request do
  let!(:account) { create(:account) }

  describe 'DELETE /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:message) { create(:message, account: account, content: 'Secret original content') }
    let(:conversation) { message.conversation }
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
    end

    it 'soft deletes the message and records an audit log with the original content' do
      expect do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.to change(Enterprise::AuditLog, :count).by(1)

      audit_log = Enterprise::AuditLog.where(auditable_type: 'Message', action: 'destroy').last

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(message.reload.content).to eq 'This message was deleted'
        expect(message.reload.deleted).to be true
        expect(audit_log.auditable_id).to eq(message.id)
        expect(audit_log.user_id).to eq(agent.id)
        expect(audit_log.associated_id).to eq(account.id)
        expect(audit_log.remote_address).to be_present
        expect(audit_log.audited_changes['content']).to eq('Secret original content')
        expect(audit_log.audited_changes['conversation_id']).to eq(message.conversation_id)
        expect(audit_log.audited_changes['display_id']).to eq(conversation.display_id)
        expect(audit_log.audited_changes['inbox_id']).to eq(message.inbox_id)
      end
    end

    it 'does not create an audit log when the message id is invalid' do
      expect do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/99999",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(Enterprise::AuditLog, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not create a duplicate audit log when an already-deleted message is deleted again' do
      path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}"

      delete path, headers: agent.create_new_auth_token, as: :json
      expect(Enterprise::AuditLog.where(auditable_type: 'Message', action: 'destroy').count).to eq(1)

      expect do
        delete path, headers: agent.create_new_auth_token, as: :json
      end.not_to change(Enterprise::AuditLog, :count)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/auto_translate' do
    let(:conversation) { create(:conversation, account: account) }
    let(:agent) { create(:user, account: account, role: :agent, ui_settings: { locale: 'es' }) }

    before do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
      account.enable_features!(:auto_translate, :captain_tasks)
      account.update!(auto_translate: true, translation_provider: 'captain')
    end

    def post_auto_translate(message_ids)
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/auto_translate",
           params: { message_ids: message_ids }, headers: agent.create_new_auth_token, as: :json
    end

    it 'enqueues translations only for incoming public text messages' do
      incoming = create(:message, conversation: conversation, message_type: :incoming, content: 'Bonjour')
      outgoing = create(:message, conversation: conversation, message_type: :outgoing, content: 'Hello')
      private_message = create(:message, conversation: conversation, message_type: :incoming, private: true, content: 'Private')
      attachment = create(:message, conversation: conversation, message_type: :incoming, content_type: :incoming_email, content: '')

      expect do
        post_auto_translate([incoming.id, outgoing.id, private_message.id, attachment.id])
      end.to have_enqueued_job(Captain::Conversation::ContactMessageTranslationJob).with(incoming, 'es')
      expect(response).to have_http_status(:accepted)
      expect(incoming.reload.content_attributes['translation_status']).to eq('pending')
    end

    it 'does not enqueue a second pending translation and allows retry after failure' do
      incoming = create(:message, conversation: conversation, message_type: :incoming, content: 'Bonjour',
                                  content_attributes: { 'translation_status' => 'pending' })

      expect do
        post_auto_translate([incoming.id])
      end.not_to have_enqueued_job(Captain::Conversation::ContactMessageTranslationJob)

      incoming.update!(content_attributes: { 'translation_status' => 'failed' })
      expect do
        post_auto_translate([incoming.id])
      end.to have_enqueued_job(Captain::Conversation::ContactMessageTranslationJob).with(incoming, 'es')
      expect(incoming.reload.content_attributes['translation_status']).to eq('pending')
    end

    it 'rejects ids not belonging to the conversation' do
      message = create(:message, message_type: :incoming)
      post_auto_translate([message.id])

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects duplicate ids and lists over the limit' do
      message = create(:message, conversation: conversation, message_type: :incoming)
      post_auto_translate([message.id, message.id])
      expect(response).to have_http_status(:unprocessable_entity)

      post_auto_translate((1..21).to_a)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
