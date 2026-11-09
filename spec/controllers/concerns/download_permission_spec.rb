# frozen_string_literal: true

require 'rails_helper'

# The point of these specs is the thing a hidden button cannot prove: that the
# endpoints themselves refuse to hand data over when the super admin has turned
# downloads off, including for a caller holding a valid admin token.
RSpec.describe 'Download permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  # Both switches ship disabled, so a fresh account starts locked down.
  describe 'a brand new account' do
    it 'has customer data downloads disabled' do
      expect(account.feature_enabled?('customer_data_export')).to be(false)
    end

    it 'has report downloads disabled' do
      expect(account.feature_enabled?('report_export')).to be(false)
    end
  end

  describe 'customer data downloads' do
    context 'when the super admin has disabled them' do
      before { account.disable_features!('customer_data_export') }

      it 'refuses a contact export' do
        post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses a conversation export' do
        post "/api/v1/accounts/#{account.id}/conversations/export", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses a CSAT download' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses/download", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses a campaign recipient export' do
        campaign = create(:campaign, account: account, inbox: create(:inbox, account: account),
                                     trigger_rules: { url: 'https://test.com' })
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/export_recipients", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses import error and skip logs' do
        account.enable_features!('data_import')
        data_import = create(:data_import, :intercom, account: account, initiated_by: admin)
        %w[error_logs skip_logs].each do |action|
          get "/api/v1/accounts/#{account.id}/data_imports/#{data_import.id}/#{action}.csv", headers: headers
          expect(response).to have_http_status(:forbidden)
        end
      end

      it 'answers with a readable reason rather than a bare status' do
        post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
        expect(response.parsed_body['error']).to be_present
      end

      it 'records the blocked attempt, since it did not come from the interface' do
        allow(Rails.logger).to receive(:warn)
        post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
        expect(Rails.logger).to have_received(:warn).with(/DownloadBlocked.*customer_data_export/)
      end
    end

    context 'when the super admin has enabled them' do
      before { account.enable_features!('customer_data_export') }

      it 'allows a contact export' do
        post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'allows a conversation export' do
        post "/api/v1/accounts/#{account.id}/conversations/export", headers: headers, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'report downloads' do
    context 'when the super admin has disabled them' do
      before { account.disable_features!('report_export') }

      it 'refuses an agent report download' do
        get "/api/v2/accounts/#{account.id}/reports/agents", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses an inbox report download' do
        get "/api/v2/accounts/#{account.id}/reports/inboxes", headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'still lets the reports be read on screen' do
        get "/api/v2/accounts/#{account.id}/reports/summary",
            params: { type: :account, since: 1.day.ago.to_i.to_s, until: Time.zone.now.to_i.to_s },
            headers: headers
        expect(response).to have_http_status(:success)
      end
    end

    context 'when the super admin has enabled them' do
      before { account.enable_features!('report_export') }

      it 'allows an agent report download' do
        get "/api/v2/accounts/#{account.id}/reports/agents",
            params: { since: 1.day.ago.to_i.to_s, until: Time.zone.now.to_i.to_s },
            headers: headers
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'the two switches are independent' do
    before do
      account.enable_features!('report_export')
      account.disable_features!('customer_data_export')
    end

    it 'lets an account keep its reports while its contact list stays locked in' do
      get "/api/v2/accounts/#{account.id}/reports/agents",
          params: { since: 1.day.ago.to_i.to_s, until: Time.zone.now.to_i.to_s },
          headers: headers
      expect(response).to have_http_status(:success)

      post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'plan-managed customer exports' do
    let(:plan) { Plan.create!(name: 'Paid', slug: 'paid', price_monthly: 19, feature_keys: %w[captain_integration customer_data_export]) }

    before { account.update!(plan: plan) }

    it 'allows a synchronized paid account to export contacts' do
      post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'refuses exports after a free downgrade with the server reason' do
      free = Plan.create!(name: 'Gratis', slug: 'gratis', feature_keys: ['captain_integration'])
      account.update!(plan: free)
      post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.downloads.disabled'))
    end

    it 'refuses exports when the owner overrides a paid plan' do
      AccountFeatureOverride.create!(account: account, created_by: admin, feature_key: 'customer_data_export',
                                     enabled: false, reason: 'Owner restriction')
      post "/api/v1/accounts/#{account.id}/contacts/export", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
