require 'rails_helper'

RSpec.describe 'Plan catalog translations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:plan) do
    Plan.create!(name: 'Catalog', slug: 'catalog', feature_keys: Plan::FEATURE_KEYS)
  end
  let(:translations) do
    %w[es en].index_with do |locale|
      JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/planCatalog.json").read).fetch('PLAN_CATALOG')
    end
  end

  it 'labels every gated and base feature and every API limit in both locales' do
    plan_id = plan.id
    get "/api/v1/accounts/#{account.id}/plans", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    catalog_plan = response.parsed_body.first
    expect(catalog_plan.fetch('id')).to eq(plan_id)
    expect(catalog_plan.fetch('base_feature_keys')).to eq(Plan::CATALOG_BASE_CAPABILITIES.pluck(:key))

    feature_keys = Plan::FEATURES.pluck(:key) + Plan::CATALOG_BASE_CAPABILITIES.pluck(:key)
    limit_keys = catalog_plan.fetch('limits').keys

    %w[es en].each do |locale|
      feature_keys.each do |key|
        expect(translations.fetch(locale).dig('FEATURES', key)).to be_present
      end
      limit_keys.each do |key|
        expect(translations.fetch(locale).dig('LIMITS', key)).to be_present
      end
    end
  end
end
