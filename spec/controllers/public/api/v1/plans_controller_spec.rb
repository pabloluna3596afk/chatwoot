require 'rails_helper'

RSpec.describe 'Public Plans API', type: :request do
  let(:allowed_origin) { 'https://paluhub.com' }
  let(:other_origin) { 'https://evil.example.com' }
  let(:forbidden_keys) { %w[id addon_agent_price addon_bot_price credit_unit_price captain_daily_tests is_active is_public is_default_trial] }

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
      expect(plan.keys).to match_array(%w[slug name description display_order state price_monthly price_yearly trial_days
                                          limits feature_keys base_feature_keys])
      expect(plan['limits'].keys).to match_array(%w[monthly_responses assistants users inboxes storage_bytes
                                                    emails_per_day trial_responses])
      expect(plan).to include('price_monthly' => 79.0, 'price_yearly' => 790.0, 'trial_days' => 15)
      expect(plan['limits']['storage_bytes']).to eq(512.megabytes)
      expect(response.parsed_body.keys).to match_array(%w[currency updated_at plans])
    end

    it 'does not leak internal ids, add-on prices, costs or payment keys anywhere' do
      get '/public/api/v1/plans'

      body = response.parsed_body
      all_keys = body['plans'].flat_map { |plan| plan_keys(plan) }.map { |key| key.split('.').last }
      expect(all_keys & forbidden_keys).to be_empty
      expect(all_keys.grep(/addon_|payphone|captain_|cost|margin|credit/)).to be_empty
      expect(response.body).not_to match(/addon_|credit_unit_price|payphone/i)
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
