require 'rails_helper'

RSpec.describe 'Public Categories API', type: :request do
  let!(:account) { create(:account) }
  let!(:portal) { create(:portal, slug: 'test-portal', custom_domain: 'www.example.com') }

  before do
    create(:category, slug: 'test-category-1', portal_id: portal.id, account_id: account.id)
    create(:category, slug: 'test-category-2', portal_id: portal.id, account_id: account.id)
    create(:category, slug: 'test-category-3', portal_id: portal.id, account_id: account.id)
  end

  describe 'GET /public/api/v1/portals/:portal_slug/categories' do
    it 'redirects to the locale home page' do
      category = portal.categories.first

      get "/hc/#{portal.slug}/#{category.locale}/categories"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("/hc/#{portal.slug}/#{category.locale}")
    end
  end

  describe 'GET /public/api/v1/portals/:portal_slug/categories/:slug' do
    it 'Fetch category with the slug' do
      category = portal.categories.first

      get "/hc/#{portal.slug}/#{category.locale}/categories/#{category.slug}"

      expect(response).to have_http_status(:success)
    end

    it 'keeps the locale switcher on a translated category when available' do
      portal.update!(config: { allowed_locales: %w[en es], default_locale: 'en' })
      category = create(:category, portal: portal, account: account, locale: 'en', slug: 'help-en')
      translated_category = create(:category, portal: portal, account: account, locale: 'es', slug: 'help-es',
                                              associated_category_id: category.id)

      get "/hc/#{portal.slug}/#{category.locale}/categories/#{category.slug}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("href=\"/hc/#{portal.slug}/es/categories/#{translated_category.slug}\"")
    end
  end
end
