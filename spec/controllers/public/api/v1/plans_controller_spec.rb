require 'rails_helper'

RSpec.describe 'Public Plans API', type: :request do
  let(:allowed_origin) { 'https://paluhub.com' }
  let(:other_origin) { 'https://evil.example.com' }
  let(:forbidden_keys) { %w[id captain_daily_tests is_active is_public is_default_trial is_recommended] }

  before do
    Plan.delete_all
    Plan.create!(name: 'Inicio', slug: 'inicio', price_monthly: 79, price_yearly: 790, display_order: 2,
                 monthly_messages: 1000, storage_mb: 512, addon_agent_price: 18, addon_bot_price: 35,
                 credit_unit_price: 0.025, feature_keys: ['captain_integration'], trial_days: 15)
    Plan.create!(name: 'Gratis', slug: 'gratis', display_order: 1)
    Plan.create!(name: 'Negocio', slug: 'negocio', price_monthly: 299, display_order: 3, coming_soon: true)
    Plan.create!(name: 'Inactivo', slug: 'inactivo', is_active: false)
    Plan.create!(name: 'Privado', slug: 'privado', is_public: false)
    Plan.create!(name: 'Developer', slug: 'developer', price_monthly: 49)
  end

  def plan_keys(hash, prefix = '')
    hash.flat_map do |key, value|
      path = "#{prefix}#{key}"
      value.is_a?(Hash) ? [path] + plan_keys(value, "#{path}.") : [path]
    end
  end

  describe 'GET /public/api/v1/plans' do
    it 'publishes active packs and editable monthly prices per public plan' do
      pack = ExtraPack.create!(bucket: :internal, units: 500, price_usd: 6)
      ExtraPack.create!(bucket: :copilot, units: 1000, price_usd: 5, active: false)
      get '/public/api/v1/plans'

      extras = response.parsed_body.fetch('extras')
      expect(extras.fetch('packs')).to eq([
                                            { 'id' => pack.id, 'bucket' => 'internal', 'units' => 500, 'price_usd' => 6.0, 'display_order' => 0,
                                              'validity_days' => 90 }
                                          ])
      expect(extras.dig('monthly', 'inicio')).to eq(
        'agent' => 18.0, 'bot' => 35.0, 'inbox' => 12.0, 'storage_100mb' => 1.0, 'storage_250mb' => 2.0
      )
      etag = response.headers['ETag']
      pack.update!(price_usd: 7)
      get '/public/api/v1/plans', headers: { 'If-None-Match' => etag }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('extras', 'packs', 0, 'price_usd')).to eq(7.0)
    end

    it 'returns the public catalog without authentication' do
      get '/public/api/v1/plans'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['currency']).to eq('USD')
      expect(body['plans'].pluck('slug')).to eq(%w[gratis inicio negocio])
      expect(body['plans'].pluck('state')).to eq(%w[available available coming_soon])
    end

    it 'never lists inactive, non-public or developer plans' do
      get '/public/api/v1/plans'

      slugs = response.parsed_body['plans'].pluck('slug')
      expect(slugs).not_to include('inactivo', 'privado', 'developer')
    end

    it 'exposes exactly the allowlisted keys per plan' do
      get '/public/api/v1/plans'

      plan = response.parsed_body['plans'].find { |p| p['slug'] == 'inicio' }
      expect(plan.keys).to match_array(%w[slug name description display_order state recommended price_monthly price_yearly
                                          addon_agent_price addon_bot_price credit_unit_price addon_inbox_price addon_storage_100mb_price
                                          addon_storage_250mb_price trial_days limits feature_keys
                                          base_feature_keys features base_features])
      expect(plan['limits'].keys).to match_array(%w[monthly_responses assistants users inboxes storage_bytes
                                                    emails_per_day trial_responses])
      expect(plan).to include('price_monthly' => 79.0, 'price_yearly' => 790.0, 'trial_days' => 15)
      expect(plan).to include('recommended' => false, 'addon_agent_price' => 18.0, 'addon_bot_price' => 35.0,
                              'credit_unit_price' => 0.025)
      expect(plan['limits']['storage_bytes']).to eq(512.megabytes)
      expect(response.parsed_body.keys).to match_array(%w[currency updated_at plans extras])
    end

    it 'returns translated feature labels and preserves the key-only fields' do
      get '/public/api/v1/plans'

      plan = response.parsed_body['plans'].find { |item| item['slug'] == 'inicio' }
      expect(plan['feature_keys']).to eq(['captain_integration'])
      expect(plan['base_feature_keys']).to include('contacts_companies')
      expect(plan['features']).to eq([{ 'key' => 'captain_integration', 'label' => 'Agente de IA' }])
      expect(plan['base_features']).to include({
                                                 'key' => 'contacts_companies', 'label' => 'Contactos y empresas'
                                               })
      labels = plan['features'].pluck('label') + plan['base_features'].pluck('label')
      expect(labels.join(' ')).not_to match(/captain/i)
    end

    it 'omits labels for unknown feature keys without changing compatibility fields' do
      plan = Plan.find_by!(slug: 'inicio')
      plan.update_column(:feature_keys, %w[captain_integration internal_unknown]) # rubocop:disable Rails/SkipsModelValidations

      get '/public/api/v1/plans'

      public_plan = response.parsed_body['plans'].find { |item| item['slug'] == 'inicio' }
      expect(public_plan['feature_keys']).to eq(%w[captain_integration internal_unknown])
      expect(public_plan['features']).to eq([{ 'key' => 'captain_integration', 'label' => 'Agente de IA' }])
    end

    it 'does not leak internal ids, costs or payment keys anywhere' do
      get '/public/api/v1/plans'

      body = response.parsed_body
      all_keys = body['plans'].flat_map { |plan| plan_keys(plan) }.map { |key| key.split('.').last }
      expect(all_keys & forbidden_keys).to be_empty
      expect(all_keys.grep(/payphone|captain_|cost|margin/)).to be_empty
      expect(response.body).not_to match(/payphone/i)
    end

    it 'returns null for nonpositive add-on prices and numbers for positive prices' do
      Plan.find_by!(slug: 'inicio').update!(addon_agent_price: 0, addon_bot_price: -2, credit_unit_price: 0.04)

      get '/public/api/v1/plans'

      plan = response.parsed_body['plans'].find { |item| item['slug'] == 'inicio' }
      expect(plan).to include('addon_agent_price' => nil, 'addon_bot_price' => nil, 'credit_unit_price' => 0.04)
    end

    it 'sends cache headers and an ETag' do
      get '/public/api/v1/plans'

      expect(response.headers['ETag']).to be_present
      cache_control = response.headers['Cache-Control']
      expect(cache_control).to include('public', 'max-age=60', 's-maxage=300',
                                       'stale-while-revalidate=86400', 'stale-if-error=86400')
    end

    it 'answers 304 when the ETag matches and a new ETag after a plan changes' do
      get '/public/api/v1/plans'
      etag = response.headers['ETag']

      get '/public/api/v1/plans', headers: { 'If-None-Match' => etag }
      expect(response).to have_http_status(:not_modified)

      Plan.find_by!(slug: 'inicio').update!(price_monthly: 89)
      get '/public/api/v1/plans', headers: { 'If-None-Match' => etag }
      expect(response).to have_http_status(:ok)
      expect(response.headers['ETag']).not_to eq(etag)
    end

    it 'changes the ETag when a plan stops being public' do
      get '/public/api/v1/plans'
      etag = response.headers['ETag']

      Plan.find_by!(slug: 'negocio').update!(is_public: false)
      get '/public/api/v1/plans'
      expect(response.headers['ETag']).not_to eq(etag)
      expect(response.parsed_body['plans'].pluck('slug')).not_to include('negocio')
    end

    it 'changes updated_at and ETag when any newly public field changes' do
      %i[addon_agent_price addon_bot_price credit_unit_price is_recommended].each do |attribute|
        get '/public/api/v1/plans'
        etag = response.headers['ETag']
        timestamp = response.parsed_body['updated_at']
        plan = Plan.find_by!(slug: 'inicio')
        value = attribute == :is_recommended ? true : plan.public_send(attribute) + 1
        plan.update!(attribute => value)

        get '/public/api/v1/plans'
        expect(response.headers['ETag']).not_to eq(etag), "expected #{attribute} to invalidate the ETag"
        expect(response.parsed_body['updated_at']).not_to eq(timestamp), "expected #{attribute} to update the catalog timestamp"
      end
    end
  end

  describe 'CORS' do
    it 'allows the website origin' do
      get '/public/api/v1/plans', headers: { 'Origin' => allowed_origin }

      expect(response.headers['Access-Control-Allow-Origin']).to eq(allowed_origin)
    end

    it 'does not allow another origin' do
      get '/public/api/v1/plans', headers: { 'Origin' => other_origin }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'answers the preflight only for the website origin and read methods' do
      options '/public/api/v1/plans', headers: { 'Origin' => allowed_origin, 'Access-Control-Request-Method' => 'GET' }
      expect(response.headers['Access-Control-Allow-Origin']).to eq(allowed_origin)
      expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')

      options '/public/api/v1/plans', headers: { 'Origin' => other_origin, 'Access-Control-Request-Method' => 'GET' }
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'keeps the wildcard rule on the other public API endpoints' do
      get "/public/api/v1/csat_survey/#{SecureRandom.uuid}", headers: { 'Origin' => other_origin }

      expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
    end
  end
end
