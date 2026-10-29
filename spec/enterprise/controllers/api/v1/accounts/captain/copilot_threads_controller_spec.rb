require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::CopilotThreads', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { account.enable_features!('captain_integration') }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/copilot_threads' do
    context 'when it is an un-authenticated user' do
      it 'does not fetch copilot threads' do
        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'fetches copilot threads for the current user' do
        # Create threads for the current agent
        create_list(:captain_copilot_thread, 3, account: account, user: agent)
        # Create threads for another user (should not be included)
        create_list(:captain_copilot_thread, 2, account: account, user: admin)

        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].length).to eq(3)

        expect(json_response[:payload].map { |thread| thread[:user][:id] }.uniq).to eq([agent.id])
      end

      it 'returns threads in descending order of creation' do
        threads = create_list(:captain_copilot_thread, 3, account: account, user: agent)

        get "/api/v1/accounts/#{account.id}/captain/copilot_threads",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].pluck(:id)).to eq(threads.reverse.pluck(:id))
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/copilot_threads' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:valid_params) { { message: 'Hello, how can you help me?', assistant_id: assistant.id, conversation_id: conversation.display_id } }

    context 'when it is an un-authenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      context 'with invalid params' do
        it 'returns error when message is blank' do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: '', assistant_id: assistant.id },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_response[:error]).to eq('Message is required')
        end

        it 'returns error when assistant_id is invalid' do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: 'Hello', assistant_id: 0 },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:not_found)
        end

        it 'does not accept an assistant from another account' do
          other_assistant = create(:captain_assistant)

          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: 'Hello', assistant_id: other_assistant.id },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:not_found)
          expect(CopilotThread.count).to be_zero
        end

        it 'rejects a malformed assistant id without creating an internal assistant' do
          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: { message: 'Hello', assistant_id: [] },
                 headers: agent.create_new_auth_token,
                 as: :json
          end.not_to change(Captain::Assistant, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      it 'lets an agent create a thread with the account internal assistant when none exists' do
        put_account_on_plan(account, monthly_messages: 2)

        expect do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: 'Help me with this account' },
               headers: agent.create_new_auth_token,
               as: :json
        end.to change(CopilotThread, :count).by(1)

        expect(response).to have_http_status(:success)
        internal_assistant = CopilotThread.last.assistant
        expect(account.internal_captain_assistants.count).to eq(1)
        expect(internal_assistant).to have_attributes(
          internal?: true,
          name: 'Copilot',
          product_name: account.name
        )
        expect(internal_assistant.documents).to be_empty
        expect(internal_assistant.inboxes).to be_empty
      end

      it 'reuses the same internal assistant on subsequent resolutions' do
        first = Captain::Copilot::AssistantResolver.new(account: account).perform
        second = Captain::Copilot::AssistantResolver.new(account: account).perform

        expect(first).to eq(second)
        expect(account.internal_captain_assistants.count).to eq(1)
      end

      it 'does not create an internal assistant when the feature flag is disabled' do
        account.disable_features!('captain_integration')

        expect do
          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: 'Help me' },
               headers: agent.create_new_auth_token,
               as: :json
        end.not_to change(Captain::Assistant, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it 'keeps an existing thread on its original assistant after a real assistant is created' do
        put_account_on_plan(account, monthly_messages: 3)
        post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
             params: { message: 'First thread' }, headers: agent.create_new_auth_token, as: :json
        internal_assistant = CopilotThread.last.assistant
        real_assistant = create(:captain_assistant, account: account)

        post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
             params: { message: 'Second thread' }, headers: agent.create_new_auth_token, as: :json

        expect(CopilotThread.order(:id).first.assistant).to eq(internal_assistant)
        expect(CopilotThread.order(:id).last.assistant).to eq(real_assistant)
      end

      context 'with valid params' do
        it 'returns error when usage limit is exceeded' do
          put_account_on_plan(account, monthly_messages: 2, used: 2)

          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: valid_params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          reset_date = account.current_usage_period.period_end.to_date
          expect(CopilotMessage.last.message['content']).to eq(
            "Your Copilot limit is reached. Suggestions are paused until #{reset_date}, when your plan resets; manual replies are still available."
          )
        end

        it 'creates a new copilot thread with initial message' do
          put_account_on_plan(account, monthly_messages: 2)

          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: valid_params,
                 headers: agent.create_new_auth_token,
                 as: :json
          end.to change(CopilotThread, :count).by(1)
             .and change(CopilotMessage, :count).by(1)

          expect(response).to have_http_status(:success)

          thread = CopilotThread.last
          expect(thread.title).to eq(valid_params[:message])
          expect(thread.user_id).to eq(agent.id)
          expect(thread.assistant_id).to eq(assistant.id)

          message = thread.copilot_messages.last
          expect(message.message).to eq({ 'content' => valid_params[:message] })

          expect(Captain::Copilot::ResponseJob).to have_been_enqueued.with(
            assistant: assistant,
            conversation_id: valid_params[:conversation_id],
            user_id: agent.id,
            copilot_thread_id: thread.id,
            message: valid_params[:message]
          )
        end

        it 'truncates the thread title but stores the full message when the message exceeds 255 characters' do
          account.limits = { captain_responses: 2 }
          account.custom_attributes = { captain_responses_usage: 0 }
          account.save!

          long_message = 'a' * 300

          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: { message: long_message, assistant_id: assistant.id, conversation_id: conversation.display_id },
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)

          thread = CopilotThread.last
          expect(thread.title).to eq(long_message.truncate(255, omission: ''))

          message = thread.copilot_messages.last
          expect(message.message).to eq({ 'content' => long_message })
        end

        it 'enqueues the dedicated reply suggestion job' do
          put_account_on_plan(account, monthly_messages: 2)
          create(:inbox_member, user: agent, inbox: inbox)

          post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
               params: valid_params.merge(request_type: 'reply_suggestion'),
               headers: agent.create_new_auth_token,
               as: :json

          thread = CopilotThread.last
          expect(Captain::Copilot::ReplySuggestionJob).to have_been_enqueued.with(
            assistant: assistant,
            conversation_id: valid_params[:conversation_id],
            user_id: agent.id,
            copilot_thread_id: thread.id
          )
        end

        it 'rejects an inaccessible reply suggestion before creating its thread' do
          put_account_on_plan(account, monthly_messages: 2)

          expect do
            post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
                 params: valid_params.merge(request_type: 'reply_suggestion'),
                 headers: agent.create_new_auth_token,
                 as: :json
          end.not_to change(CopilotThread, :count)

          expect(response).to have_http_status(:not_found)
          expect(CopilotMessage.count).to be_zero
          expect(Captain::Copilot::ReplySuggestionJob).not_to have_been_enqueued
        end
      end
    end
  end
end
