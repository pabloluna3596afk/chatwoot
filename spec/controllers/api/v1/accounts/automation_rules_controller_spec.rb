require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::AutomationRulesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox_id: inbox.id, contact_id: contact.id) }

  describe 'POST /api/v1/accounts/{account.id}/automation_rules/reach_preview' do
    let(:url) { "/api/v1/accounts/#{account.id}/automation_rules/reach_preview" }
    let(:schedule) do
      { kind: 'contact_date', target_inbox_id: inbox.id, date_source: 'contact_attribute', attribute_key: 'birthday' }
    end

    it 'requires authentication' do
      post url, params: { schedule: schedule }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects account agents' do
      agent = create(:user, account: account, role: :agent)

      post url, headers: agent.create_new_auth_token, params: { schedule: schedule }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects administrators of another account' do
      other_administrator = create(:user, account: create(:account), role: :administrator)

      post url, headers: other_administrator.create_new_auth_token, params: { schedule: schedule }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'counts only account contacts and preserves count alongside the diagnostics' do
      contact.update!(custom_attributes: { 'birthday' => Time.zone.today.to_s })
      create(:contact, custom_attributes: contact.custom_attributes)

      expect do
        post url, headers: administrator.create_new_auth_token, params: { schedule: schedule }, as: :json
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'count' => 1, 'candidates' => 1, 'with_open_window' => 0, 'window_closed' => 0, 'excluded_by_test_mode' => 0
      )
    end

    it 'does not use an inbox belonging to another account' do
      other_inbox = create(:inbox)
      create(:contact, account: other_inbox.account, custom_attributes: { 'birthday' => Time.zone.today.to_s })

      post url, headers: administrator.create_new_auth_token,
                params: { schedule: schedule.merge(target_inbox_id: other_inbox.id) }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'count' => 0, 'candidates' => 0, 'with_open_window' => 0, 'window_closed' => 0, 'excluded_by_test_mode' => 0
      )
    end
  end

  describe 'contact recipe save warnings' do
    let(:url) { "/api/v1/accounts/#{account.id}/automation_rules" }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false)
    end
    let(:target_inbox) { channel.inbox }
    let(:schedule) do
      { kind: 'contact_date', target_inbox_id: target_inbox.id, date_source: 'contact_attribute', attribute_key: 'birthday' }
    end
    let(:payload) do
      { name: 'Birthday', event_name: 'time_triggered', conditions: [], schedule: schedule,
        actions: [{ action_name: 'send_message', action_params: ['Hello'] }] }
    end

    it 'saves free text for WhatsApp Cloud with an additive warning' do
      post url, headers: administrator.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:success)
      rule = account.automation_rules.sole
      expect(rule.actions.first['action_name']).to eq('send_message')
      expect(response.parsed_body).to include(
        'id' => rule.id, 'name' => 'Birthday', 'warnings' => ['whatsapp_template_recommended'],
        'automation_rule_warnings' => []
      )
    end

    it 'preserves the update payload and warns even when actions are omitted from the request' do
      rule = create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [],
                                      schedule: schedule, actions: payload[:actions])

      patch "#{url}/#{rule.id}", headers: administrator.create_new_auth_token, params: { name: 'Anniversary' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('warnings' => ['whatsapp_template_recommended'], 'automation_rule_warnings' => [])
      expect(response.parsed_body['payload']).to include('id' => rule.id, 'name' => 'Anniversary')
    end

    it 'does not warn for a template and clears the warning when free text is replaced' do
      rule = create(:automation_rule, account: account, event_name: 'time_triggered', conditions: [],
                                      schedule: schedule, actions: payload[:actions])
      actions = [{ action_name: 'send_whatsapp_template', action_params: [{
        inbox_id: target_inbox.id, name: 'sample_shipping_confirmation', language: 'en_US',
        processed_params: { body: { '1' => '3' } }
      }] }]

      patch "#{url}/#{rule.id}", headers: administrator.create_new_auth_token, params: { actions: actions }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('warnings')
      expect(rule.reload.actions.first['action_name']).to eq('send_whatsapp_template')

      post url, headers: administrator.create_new_auth_token, params: payload.merge(actions: actions), as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).not_to have_key('warnings')
    end

    it 'does not warn for a conversation-based rule' do
      post url, headers: administrator.create_new_auth_token,
                params: payload.except(:schedule).merge(event_name: 'conversation_created'), as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).not_to have_key('warnings')
    end

    context 'with another channel' do
      let(:target_inbox) { inbox }

      it 'preserves the existing response without a recipe warning' do
        post url, headers: administrator.create_new_auth_token, params: payload, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).not_to have_key('warnings')
      end
    end

    context 'with the default WhatsApp provider' do
      let(:channel) do
        create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      end

      it 'does not recommend a Cloud template for a different provider' do
        post url, headers: administrator.create_new_auth_token, params: payload, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).not_to have_key('warnings')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/automation_rules/simulate' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:simulation_params) { { conversation_id: conversation.id, event_name: 'conversation_created' } }
    let(:url) { "/api/v1/accounts/#{account.id}/automation_rules/simulate" }

    it 'requires authentication' do
      post url, params: simulation_params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects agents who are not administrators like the other rule endpoints' do
      agent = create(:user, account: account, role: :agent)

      post url, headers: agent.create_new_auth_token, params: simulation_params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'forbids administrators of other accounts' do
      other_administrator = create(:user, account: create(:account), role: :administrator)

      post url, headers: other_administrator.create_new_auth_token, params: simulation_params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not expose conversations from another account' do
      other_conversation = create(:conversation)

      post url, headers: administrator.create_new_auth_token,
                params: simulation_params.merge(conversation_id: other_conversation.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not resolve a foreign display id when there is no account conversation with that display id' do
      other_conversation = create(:conversation)

      post url, headers: administrator.create_new_auth_token,
                params: { conversation_display_id: other_conversation.display_id, event_name: 'conversation_created' }

      expect(response).to have_http_status(:not_found)
    end

    it 'does not offer contact date simulation through the conversation simulator' do
      post url, headers: administrator.create_new_auth_token,
                params: simulation_params.merge(event_name: 'time_triggered')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['supported']).not_to include('time_triggered')
    end

    it 'returns additive diagnostics to an administrator without disabling the rule' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_created')
      rule.update_columns(conditions: [ # rubocop:disable Rails/SkipsModelValidations
                            { 'attribute_key' => 'status', 'filter_operator' => 'unsupported', 'values' => ['open'] }
                          ])

      2.times { post url, headers: administrator.create_new_auth_token, params: simulation_params }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['matches']).to eq([])
      expect(body['evaluated_count']).to eq(1)
      expect(body['diagnostics'].first).to include('rule_id' => rule.id, 'condition_index' => 0, 'attribute_key' => 'status')
      expect(rule.reload.active).to be(true)
    end

    it 'preserves the valid match response with an empty diagnostics array' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_created', conditions: [],
                                      actions: [{ 'action_name' => 'send_message', 'action_params' => ['Hello'] }])

      post url, headers: administrator.create_new_auth_token, params: simulation_params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'event_name' => 'conversation_created', 'conversation_id' => conversation.id,
        'evaluated_count' => 1, 'diagnostics' => [],
        'matches' => [{ 'rule_id' => rule.id, 'rule_name' => rule.name, 'order' => 1,
                        'actions' => [{ 'action_name' => 'send_message', 'action_params' => ['Hello'] }] }]
      )
    end
  end

  describe 'saving the automation contract' do
    let(:url) { "/api/v1/accounts/#{account.id}/automation_rules" }
    let(:rule) { create(:automation_rule, account: account) }
    let(:valid_params) do
      { name: 'Contract rule', event_name: 'conversation_created', conditions: [],
        actions: [{ action_name: 'send_message', action_params: ['Hello'] }] }
    end

    it 'returns indexed condition errors on create and update' do
      conditions = [{ attribute_key: 'content', filter_operator: 'equal_to', values: ['hello'] }]
      payload = valid_params.merge(conditions: conditions)
      headers = administrator.create_new_auth_token

      post url, headers: headers, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['conditions'].first).to include('Condition 0:')

      patch "#{url}/#{rule.id}", headers: headers, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['conditions'].first).to include('Condition 0:')
      expect(rule.reload.active).to be(true)
    end

    it 'returns 422 for unsupported events, operators, schedule kinds and actions' do
      invalid_payloads = [
        { event_name: 'contact_created' },
        { conditions: [{ attribute_key: 'status', filter_operator: 'contains', values: ['open'] }] },
        { event_name: 'time_triggered', schedule: { kind: 'unknown' } },
        { actions: [{ action_name: 'unknown' }] },
        { actions: [{ action_name: 'send_message', action_params: [] }] }
      ]
      headers = administrator.create_new_auth_token
      invalid_payloads.each do |invalid|
        post url, headers: headers, params: valid_params.merge(invalid), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end
      expect(account.automation_rules.count).to eq(0)
    end

    it 'allows renaming and toggling legacy rules through the API' do
      rule.update_columns(event_name: 'unsupported', # rubocop:disable Rails/SkipsModelValidations
                          conditions: [{ attribute_key: 'deleted', filter_operator: 'unsupported' }],
                          actions: [{ action_name: 'deleted' }])
      headers = administrator.create_new_auth_token
      [{ active: false }, { active: true }, { name: 'Renamed legacy rule' }].each do |changes|
        patch "#{url}/#{rule.id}", headers: headers, params: changes, as: :json

        expect(response).to have_http_status(:ok)
      end
      expect(rule.reload.name).to eq('Renamed legacy rule')
      expect(rule.active).to be(true)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/automation_rules' do
    context 'when it is an authenticated user' do
      it 'returns all records' do
        automation_rule = create(:automation_rule, account: account, name: 'Test Automation Rule')

        get "/api/v1/accounts/#{account.id}/automation_rules",
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:payload].first[:id]).to eq(automation_rule.id)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/automation_rules"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/automation_rules' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/automation_rules"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          'name': 'Notify Conversation Created and mark priority query',
          'description': 'Notify all administrator about conversation created and mark priority query',
          'event_name': 'conversation_created',
          'conditions': [
            {
              'attribute_key': 'browser_language',
              'filter_operator': 'equal_to',
              'values': ['en'],
              'query_operator': 'AND'
            },
            {
              'attribute_key': 'country_code',
              'filter_operator': 'equal_to',
              'values': %w[USA UK],
              'query_operator': nil
            }
          ],
          'actions': [
            {
              'action_name': :send_message,
              'action_params': ['Welcome to the chatwoot platform.']
            },
            {
              'action_name': :assign_team,
              'action_params': [1]
            },
            {
              'action_name': :remove_assigned_agent
            },
            {
              'action_name': :remove_assigned_team
            },
            {
              'action_name': :add_label,
              'action_params': %w[support priority_customer]
            }
          ]
        }
      end

      it 'processes invalid query operator' do
        expect(account.automation_rules.count).to eq(0)
        params[:conditions] << {
          'attribute_key': 'browser_language',
          'filter_operator': 'equal_to',
          'values': ['en'],
          'query_operator': 'invalid'
        }

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.automation_rules.count).to eq(0)
      end

      it 'throws an error for unknown attributes in condtions' do
        expect(account.automation_rules.count).to eq(0)
        params[:conditions] << {
          'attribute_key': 'unknown_attribute',
          'filter_operator': 'equal_to',
          'values': ['en'],
          'query_operator': 'AND'
        }

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.automation_rules.count).to eq(0)
      end

      it 'Saves for automation_rules for account with country_code and browser_language conditions' do
        expect(account.automation_rules.count).to eq(0)

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.count).to eq(1)
      end

      it 'Saves for automation_rules for account with status conditions' do
        params[:conditions] = [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['resolved'],
            query_operator: nil
          }
        ]
        expect(account.automation_rules.count).to eq(0)

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.count).to eq(1)
      end

      it 'Saves file in the automation actions to send an attachments' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )

        expect(account.automation_rules.count).to eq(0)

        params[:actions] = [
          {
            'action_name': :send_message,
            'action_params': ['Welcome to the chatwoot platform.']
          },
          {
            'action_name': :send_attachment,
            'action_params': [blob.signed_id]
          }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        automation_rule = account.automation_rules.first
        expect(automation_rule.files.presence).to be_truthy
        expect(automation_rule.files.count).to eq(1)
      end

      it 'Saves files in the automation actions to send multiple attachments' do
        blob_1 = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )
        blob_2 = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/sample.png').open,
          filename: 'sample.png',
          content_type: 'image/png'
        )

        params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': [blob_1.signed_id]
          },
          {
            'action_name': :send_attachment,
            'action_params': [blob_2.signed_id]
          }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        automation_rule = account.automation_rules.first
        expect(automation_rule.files.count).to eq(2)
      end

      it 'returns error for invalid attachment blob_id' do
        params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': ['invalid_blob_id']
          }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.attachments.invalid'))
      end

      it 'stores the original blob_id in action_params after create' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )

        params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': [blob.signed_id]
          }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: params

        automation_rule = account.automation_rules.first
        attachment_action = automation_rule.actions.find { |a| a['action_name'] == 'send_attachment' }
        expect(attachment_action['action_params'].first).to be_a(Integer)
        expect(attachment_action['action_params'].first).to eq(automation_rule.files.first.blob_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/automation_rules/{automation_rule.id}' do
    let!(:automation_rule) { create(:automation_rule, account: account, name: 'Test Automation Rule') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns for automation_rule for account' do
        expect(account.automation_rules.count).to eq(1)

        get "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:payload]).to be_present
        expect(body[:payload][:id]).to eq(automation_rule.id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/automation_rules/{automation_rule.id}/clone' do
    let!(:automation_rule) { create(:automation_rule, account: account, name: 'Test Automation Rule') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}/clone"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns for cloned automation_rule for account' do
        expect(account.automation_rules.count).to eq(1)

        post "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}/clone",
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:payload]).to be_present
        expect(body[:payload][:id]).not_to eq(automation_rule.id)
        expect(account.automation_rules.count).to eq(2)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/automation_rules/{automation_rule.id}' do
    let!(:automation_rule) { create(:automation_rule, account: account, name: 'Test Automation Rule') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:update_params) do
        {
          'description': 'Update description',
          'name': 'Update name',
          'conditions': [
            {
              'attribute_key': 'browser_language',
              'filter_operator': 'equal_to',
              'values': ['en'],
              'query_operator': 'AND'
            }
          ],
          'actions': [
            {
              'action_name': :add_label,
              'action_params': %w[support priority_customer]
            }
          ]
        }
      end

      it 'returns for cloned automation_rule for account' do
        expect(account.automation_rules.count).to eq(1)
        expect(account.automation_rules.first.actions.size).to eq(4)

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: update_params

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:payload][:name]).to eq('Update name')
        expect(body[:payload][:description]).to eq('Update description')
        expect(body[:payload][:conditions].size).to eq(1)
        expect(body[:payload][:actions].size).to eq(1)
      end

      it 'returns for updated active flag for automation_rule' do
        expect(automation_rule.active).to be(true)
        params = { active: false }

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: params

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:payload][:active]).to be(false)
        expect(automation_rule.reload.active).to be(false)
      end

      it 'allows update with existing blob_id' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )

        automation_rule.update!(actions: [{ 'action_name' => 'send_attachment', 'action_params' => [blob.id] }])
        automation_rule.files.attach(blob)

        update_params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': [blob.id]
          }
        ]

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: update_params

        expect(response).to have_http_status(:success)
      end

      it 'returns error for invalid blob_id on update' do
        update_params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': [999_999]
          }
        ]

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: update_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.attachments.invalid'))
      end

      it 'allows adding new attachment on update with signed blob_id' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )

        update_params[:actions] = [
          {
            'action_name': :send_attachment,
            'action_params': [blob.signed_id]
          }
        ]

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: update_params

        expect(response).to have_http_status(:success)
        expect(automation_rule.reload.files.count).to eq(1)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/automation_rules/{automation_rule.id}' do
    let!(:automation_rule) { create(:automation_rule, account: account, name: 'Test Automation Rule') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'delete the automation_rule for account' do
        expect(account.automation_rules.count).to eq(1)

        delete "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
               headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.count).to eq(0)
      end
    end
  end

  describe 'execution_delay handling' do
    let(:delayed_rule_params) do
      {
        name: 'Delayed rule',
        event_name: 'conversation_updated',
        execution_delay: 240,
        conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }],
        actions: [{ action_name: 'add_label', action_params: ['stale'] }]
      }
    end

    context 'when the delayed_automations feature is enabled' do
      before { account.enable_features!('delayed_automations') }

      it 'persists and serializes execution_delay' do
        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: delayed_rule_params

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:execution_delay]).to eq(240)
        expect(account.automation_rules.last.execution_delay).to eq(240)
      end

      it 'persists and serializes a delayed customer follow-up with a pending status condition' do
        conditions = [
          { attribute_key: 'message_type', filter_operator: 'equal_to', values: ['outgoing'], query_operator: 'and' },
          { attribute_key: 'private_note', filter_operator: 'equal_to', values: [false], query_operator: 'and' },
          { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: 'and' },
          { attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: delayed_rule_params.merge(event_name: 'message_created', conditions: conditions),
             as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:conditions]).to eq(conditions)
        expect(account.automation_rules.last.conditions.map(&:deep_symbolize_keys)).to eq(conditions)
      end

      it 'persists a delayed message rule with label conditions' do
        conditions = [
          { attribute_key: 'message_type', filter_operator: 'equal_to', values: ['outgoing'], query_operator: 'and' },
          { attribute_key: 'labels', filter_operator: 'equal_to', values: ['feature'], query_operator: nil }
        ]

        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: delayed_rule_params.merge(event_name: 'message_created', conditions: conditions),
             as: :json

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.last.conditions.map(&:deep_symbolize_keys)).to eq(conditions)
      end

      it 'can deactivate an existing delayed message rule with label conditions' do
        automation_rule = create(
          :automation_rule,
          account: account,
          event_name: 'message_created',
          execution_delay: 240,
          conditions: [
            { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['outgoing'],
              'query_operator' => 'and' },
            { 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['feature'], 'query_operator' => nil }
          ]
        )

        patch "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}",
              headers: administrator.create_new_auth_token,
              params: { active: false }

        expect(response).to have_http_status(:success)
        expect(automation_rule.reload).not_to be_active
      end

      it 'copies execution_delay on clone' do
        automation_rule = create(:automation_rule, account: account, execution_delay: 240)

        post "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}/clone",
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.last.execution_delay).to eq(240)
      end
    end

    context 'when the delayed_automations feature is disabled' do
      it 'rejects a payload carrying execution_delay with 422' do
        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: delayed_rule_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.automation_rules.count).to eq(0)
      end

      it 'still accepts payloads without execution_delay' do
        post "/api/v1/accounts/#{account.id}/automation_rules",
             headers: administrator.create_new_auth_token,
             params: delayed_rule_params.except(:execution_delay)

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.last.execution_delay).to be_nil
      end

      it 'rejects cloning an existing delayed rule instead of turning it into an instant one' do
        automation_rule = create(:automation_rule, account: account, execution_delay: 240)

        post "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}/clone",
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.automation_rules.count).to eq(1)
      end

      it 'still clones a rule that carries no delay' do
        automation_rule = create(:automation_rule, account: account)

        post "/api/v1/accounts/#{account.id}/automation_rules/#{automation_rule.id}/clone",
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(account.automation_rules.count).to eq(2)
      end
    end
  end
end
