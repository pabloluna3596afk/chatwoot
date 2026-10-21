require 'rails_helper'

RSpec.describe 'Calendar association authorization', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:connection) do
    CalendarConnection.create!(account: account, provider: 'google', email: 'calendar@example.com', refresh_token: 'refresh',
                               access_token: 'access', access_token_expires_at: 1.hour.from_now)
  end
  let(:client) { instance_double(Integrations::GoogleCalendar::Client) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/events" }
  let(:headers) { agent.create_new_auth_token }
  let(:params) do
    { connection_id: connection.id, calendar_id: 'main', summary: 'Consultation',
      start: '2030-01-15T10:00:00-05:00', end: '2030-01-15T10:30:00-05:00',
      contact_id: conversation.contact_id, conversation_id: conversation.display_id, send_to_contact: true }
  end
  let(:record) do
    connection.calendar_events.create!(account: account, external_calendar_id: 'main', google_event_id: 'private-event',
                                       summary: 'Original', start_at: Time.iso8601(params[:start]), end_at: Time.iso8601(params[:end]),
                                       conversation: conversation, contact: conversation.contact, idempotency_key: 'original-key')
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'main', summary: 'Main', is_enabled: true)
    allow(Integrations::GoogleCalendar::Client).to receive(:new).and_return(client)
    allow(client).to receive(:list_events).and_return([])
    allow(client).to receive(:create_event) do |**attributes|
      { 'id' => 'new-event', 'summary' => attributes[:summary], 'start' => { 'dateTime' => params[:start] },
        'end' => { 'dateTime' => params[:end] } }
    end
    allow(client).to receive(:update_event) do |**attributes|
      { 'id' => attributes[:event_id], 'summary' => attributes[:summary], 'start' => { 'dateTime' => params[:start] },
        'end' => { 'dateTime' => params[:end] } }
    end
    allow(client).to receive(:delete_event).and_return({})
    allow(Conversations::ActivityMessageJob).to receive(:perform_later)
    allow(Calendar::NotifyPanelAiFollowupJob).to receive(:perform_later)
  end

  after do
    %w[private-event new-event].each do |id|
      Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: id))
    end
  end

  shared_examples 'denied mutations' do
    [:create, :update, :cancel, :patch_cancel].each do |operation|
      it "rejects #{operation} with the existing Pundit contract and no effects", :aggregate_failures do
        record
        original = record.reload.attributes
        request_params = params.merge(appointment_status: 'cancelled', note: 'Requested') if operation == :patch_cancel
        request_params ||= params.merge(note: 'Requested')
        case operation
        when :create then post url, headers: headers, params: request_params, as: :json
        when :cancel then delete "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
        else patch "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
        end

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
        expect(client).not_to have_received(:create_event)
        expect(client).not_to have_received(:update_event)
        expect(client).not_to have_received(:delete_event)
        expect(record.reload.attributes).to eq(original)
        expect(CalendarEvent.count).to eq(1)
        expect(CalendarEventActivity.count).to eq(0)
        expect(conversation.messages.count).to eq(0)
        expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
        expect(Calendar::NotifyPanelAiFollowupJob).not_to have_received(:perform_later)
      end
    end
  end

  it_behaves_like 'denied mutations'

  context 'when bypassing the saved conversation through request associations' do
    operations = [:update, :cancel, :patch_cancel]
    [nil, :omit, :replace].each do |association|
      operations.each do |operation|
        it "rejects #{operation} with #{association.inspect} associations" do
          record
          original = record.reload.attributes
          request_params = params.except(:conversation_id, :contact_id).merge(note: 'Requested')
          request_params[:conversation_id] = nil if association.nil?
          if association == :replace
            accessible = create(:conversation, account: account)
            create(:inbox_member, inbox: accessible.inbox, user: agent)
            request_params[:conversation_id] = accessible.display_id
            request_params[:contact_id] = accessible.contact_id
          end
          request_params[:appointment_status] = 'cancelled' if operation == :patch_cancel
          if operation == :cancel
            delete "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
          else
            patch "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
          end

          expect(response).to have_http_status(:unauthorized)
          expect(client).not_to have_received(:update_event)
          expect(client).not_to have_received(:delete_event)
          expect(record.reload.attributes).to eq(original)
          expect(record.activities).to be_empty
          expect(conversation.messages.count).to eq(0)
          expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
        end
      end
    end
  end

  it 'authorizes the saved event before returning an idempotent booking' do
    record
    post url, headers: headers,
              params: params.except(:conversation_id, :contact_id).merge(idempotency_key: 'original-key'), as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(client).not_to have_received(:create_event)
    expect(record.activities).to be_empty
    expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
  end

  context 'with conversation access' do
    before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

    [:create, :update, :cancel].each do |operation|
      it "rejects a mismatched contact on #{operation} before Google", :aggregate_failures do
        record
        original = record.reload.attributes
        other_contact = create(:contact, account: account)
        request_params = params.merge(contact_id: other_contact.id, note: 'Requested')
        case operation
        when :create then post url, headers: headers, params: request_params, as: :json
        when :cancel then delete "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
        else patch "#{url}/#{record.google_event_id}", headers: headers, params: request_params, as: :json
        end

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('integration_apps.calendars.contact_mismatch'))
        expect(client).not_to have_received(:create_event)
        expect(client).not_to have_received(:update_event)
        expect(client).not_to have_received(:delete_event)
        expect(record.reload.attributes).to eq(original)
        expect(record.activities).to be_empty
        expect(conversation.messages.count).to eq(0)
        expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
      end
    end

    [:contact_id, :conversation_id, :connection_id].each do |foreign_key|
      it "does not resolve #{foreign_key} from another account" do
        other_conversation = create(:conversation)
        foreign_id = case foreign_key
                     when :contact_id then other_conversation.contact_id
                     when :conversation_id then other_conversation.display_id + conversation.display_id + 1000
                     else create(:calendar_connection).id
                     end
        other_conversation.update!(display_id: foreign_id) if foreign_key == :conversation_id

        post url, headers: headers, params: params.merge(foreign_key => foreign_id), as: :json

        expect(response).to have_http_status(:not_found)
        expect(client).not_to have_received(:create_event)
        expect(CalendarEvent.count).to eq(0)
        expect(CalendarEventActivity.count).to eq(0)
        expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
      end
    end
  end

  [:admin, :agent, :bot].each do |actor|
    context "with valid #{actor} authorization" do
      let(:headers) { actor == :bot ? { api_access_token: bot.access_token.token } : public_send(actor).create_new_auth_token }

      before { create(:inbox_member, inbox: conversation.inbox, user: agent) if actor == :agent }

      it 'creates, edits and cancels an associated appointment', :aggregate_failures do
        post url, headers: headers, params: params, as: :json
        expect(response).to have_http_status(:ok)
        saved = connection.calendar_events.find_by!(google_event_id: 'new-event')
        expect(saved).to have_attributes(contact_id: conversation.contact_id, conversation_id: conversation.id)

        patch "#{url}/new-event", headers: headers, params: params.merge(summary: 'Updated'), as: :json
        expect(response).to have_http_status(:ok)
        expect(saved.reload.summary).to eq('Updated')

        delete "#{url}/new-event", headers: headers, params: params.merge(note: 'Requested'), as: :json
        expect(response).to have_http_status(:ok)
        expect(saved.reload.appointment_status).to eq('cancelled')
        expect(saved.activities.pluck(:action)).to eq(%w[created updated deleted])
        expect(client).to have_received(:create_event).once
        expect(client).to have_received(:update_event).once
        expect(client).to have_received(:delete_event).once
      end
    end
  end

  context 'with an Enterprise participating-only role', if: ChatwootApp.enterprise? do
    before do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
      role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
      agent.account_users.find_by!(account: account).update!(custom_role: role)
    end

    it_behaves_like 'denied mutations'

    it 'rejects changing the saved event even when the request omits associations' do
      record
      patch "#{url}/#{record.google_event_id}", headers: headers,
                                                params: params.except(:conversation_id, :contact_id), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(client).not_to have_received(:update_event)
      expect(record.reload.summary).to eq('Original')
      expect(record.activities).to be_empty
      expect(Conversations::ActivityMessageJob).not_to have_received(:perform_later)
    end

    it 'permits a participating agent to create an associated appointment' do
      create(:conversation_participant, account: account, conversation: conversation, user: agent)
      post url, headers: headers, params: params, as: :json

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:create_event).once
    end
  end
end
