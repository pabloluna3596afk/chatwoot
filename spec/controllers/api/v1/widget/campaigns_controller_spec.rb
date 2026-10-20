require 'rails_helper'

RSpec.describe '/api/v1/widget/campaigns', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let!(:campaign_1) { create(:campaign, inbox: web_widget.inbox, enabled: true, account: account, trigger_rules: { url: 'https://test.com' }) }
  let!(:campaign_2) { create(:campaign, inbox: web_widget.inbox, enabled: false, account: account, trigger_rules: { url: 'https://test.com' }) }

  describe 'GET /api/v1/widget/campaigns' do
    let(:params) { { website_token: web_widget.website_token } }

    context 'when campaigns feature is enabled' do
      before do
        account.enable_features!('campaigns')
      end

      it 'returns the list of enabled campaigns' do
        get '/api/v1/widget/campaigns', params: params

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.length).to eq 1
        expect(json_response.pluck('id')).to include(campaign_1.display_id)
        expect(json_response.pluck('id')).not_to include(campaign_2.display_id)
      end
    end

    context 'when campaigns feature is disabled' do
      before do
        account.disable_features!('campaigns')
      end

      it 'returns empty array' do
        get '/api/v1/widget/campaigns', params: params

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to eq []
      end
    end

    context 'with invalid website token' do
      it 'returns not found status' do
        get '/api/v1/widget/campaigns', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  it 'reproduces MV-15: resolves public campaign values using the account timezone' do
    account.enable_features!('campaigns')
    account.update!(reporting_timezone: 'America/Guayaquil')
    campaign_1.update!(message: '{{ account.name }} / {{ inbox.name }} / {{ date.today }}')
    travel_to Time.utc(2026, 10, 20, 2) do
      get '/api/v1/widget/campaigns', params: { website_token: web_widget.website_token }
      expect(response.parsed_body.sole.fetch('message')).to eq("#{account.name} / #{web_widget.inbox.name} / 2026-10-19")
    end
  end

  it 'never includes visitor data, raw Liquid or null entries in the shared response' do
    account.enable_features!('campaigns')
    campaign_1.update!(message: 'Hola {{ contact.name }}')
    create(:contact, account: account, name: 'Private Visitor', email: 'private@example.com')
    get '/api/v1/widget/campaigns', params: { website_token: web_widget.website_token }
    expect(response.parsed_body).to eq([])
    expect(Conversation.count).to eq(0)
  end
end
