require 'rails_helper'

RSpec.describe 'Public Articles API', type: :request do
  let!(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, slug: 'test-portal', config: { allowed_locales: %w[en es] }, custom_domain: 'www.example.com') }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, locale: 'en', slug: 'category_slug') }
  let!(:category_2) { create(:category, name: 'category', portal: portal, account_id: account.id, locale: 'es', slug: 'category_slug') }
  let!(:article) do
    create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id,
                     content: 'This is a *test* content with ^markdown^', views: 0)
  end

  before do
    ENV['HELPCENTER_URL'] = ENV.fetch('FRONTEND_URL', nil)
    create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id, views: 15)
    create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id, associated_article_id: article.id, views: 1)
    create(:article, category: category_2, portal: portal, account_id: account.id, author_id: agent.id, associated_article_id: article.id, views: 5)
    create(:article, category: category_2, portal: portal, account_id: account.id, author_id: agent.id, views: 4)
    create(:article, category: category_2, portal: portal, account_id: account.id, author_id: agent.id, status: :draft)
  end

  describe 'GET /public/api/v1/portals/:slug/articles' do
    it 'Fetch all articles in the portal' do
      get "/hc/#{portal.slug}/#{category.locale}/categories/#{category.slug}/articles"
      expect(response).to have_http_status(:success)
    end

    it 'Fetches only the published articles in the portal' do
      get "/hc/#{portal.slug}/#{category_2.locale}/categories/#{category.slug}/articles.json"
      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(2)
    end

    it 'get all articles with searched text query' do
      long_content = ([('intro ' * 30).strip, 'funny', ('tail ' * 30).strip].join(' ')).strip
      create(:article,
             account_id: account.id,
             portal: portal,
             category: category,
             author_id: agent.id,
             content: long_content)

      get "/hc/#{portal.slug}/#{category.locale}/categories/#{category.slug}/articles.json", params: { query: 'funny' }
      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(1)
      expect(response_data[0].keys).to match_array(%i[id category_id title content link])
      expect(response_data[0][:content]).to include('funny')
      expect(response_data[0][:content].length).to be < long_content.length
    end

    it 'limits search results to the current locale' do
      create(:article,
             account_id: account.id,
             portal: portal,
             category: category,
             author_id: agent.id,
             title: 'English locale result',
             content: 'shared-search-term in english')
      create(:article,
             account_id: account.id,
             portal: portal,
             category: category_2,
             author_id: agent.id,
             title: 'Spanish locale result',
             content: 'shared-search-term in spanish')

      get "/hc/#{portal.slug}/#{category.locale}/articles.json", params: { query: 'shared-search-term' }

      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.pluck(:title)).to eq(['English locale result'])
    end

    it 'treats whitespace-only queries as empty searches' do
      get "/hc/#{portal.slug}/#{category.locale}/articles.json", params: { query: '   ' }

      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(3)
      expect(response_data.first).to include(:description, :slug, :portal)
    end

    it 'get all popular articles if sort params is passed' do
      get "/hc/#{portal.slug}/#{category.locale}/articles.json", params: { sort: 'views' }

      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(3)
      expect(response_data[0][:views]).to eq(15)
      expect(response_data[1][:views]).to eq(1)
      expect(response_data.last[:id]).to eq(article.id)
    end

    it 'limits results based on per_page parameter' do
      get "/hc/#{portal.slug}/#{category.locale}/articles.json", params: { per_page: 2 }

      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(2)
      # Only count articles in the current locale (category.locale is 'en')
      expect(JSON.parse(response.body, symbolize_names: true)[:meta][:articles_count]).to eq(3)
    end

    it 'returns articles count from all locales when locale parameter is not present' do
      get "/hc/#{portal.slug}/articles.json"

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body, symbolize_names: true)[:meta][:articles_count]).to eq(5)
    end

    it 'excludes unpublished translations from public responses' do
      %i[draft archived].each do |status|
        create(:article, portal: portal, author: agent, associated_article_id: article.id,
                         status: status, title: "Hidden #{status}", content: "Private #{status}")
      end

      get "/hc/#{portal.slug}/#{category.locale}/articles.json"

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      published_ids = article.associated_articles.published.pluck(:id)
      associated_ids = payload.find { |entry| entry['id'] == article.id }['associated_articles'].pluck('id')
      expect(associated_ids).to match_array(published_ids)
      expect(response.body).not_to include('Hidden draft', 'Hidden archived', 'Private draft', 'Private archived')
    end

    it 'uses default items per page if per_page is less than 1' do
      get "/hc/#{portal.slug}/#{category.locale}/articles.json", params: { per_page: 0 }

      expect(response).to have_http_status(:success)
      response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
      expect(response_data.length).to eq(3)
    end
  end

  describe 'GET /public/api/v1/portals/:slug/articles/:id' do
    it 'Fetch article with the id' do
      get "/hc/#{portal.slug}/articles/#{article.slug}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(ChatwootMarkdownRenderer.new(article.content).render_article)
      expect(article.reload.views).to eq 0 # View count should not increment on show
    end

    %i[draft archived].each do |status|
      it "returns not found for a #{status} article without a preview token" do
        unpublished_article = create(:article, category: category, status: status, portal: portal, author: agent)

        get "/hc/#{portal.slug}/articles/#{unpublished_article.slug}"
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include(I18n.t('public_portal.404.title'))

        get "/hc/#{portal.slug}/articles/#{unpublished_article.slug}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "renders a #{status} article with its preview token" do
        unpublished_article = create(:article, category: category, status: status, portal: portal, author: agent, content: 'Unreleased content')

        get "/hc/#{portal.slug}/articles/#{unpublished_article.slug}", params: { preview_token: unpublished_article.preview_token }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Unreleased content')
      end
    end

    it 'returns not found for a preview token of an article in another portal' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)
      foreign_article = create(:article, status: :draft)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: foreign_article.preview_token }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns not found for a preview token used on another article URL' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)
      other_draft = create(:article, category: category, status: :draft, portal: portal, author: agent)

      get "/hc/#{portal.slug}/articles/#{other_draft.slug}", params: { preview_token: draft_article.preview_token }

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects tampered tokens and tokens with another purpose' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)
      ["#{draft_article.preview_token}tampered", draft_article.signed_id(purpose: :other)].each do |token|
        get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: token }
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'returns not found when the preview token has expired' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)
      preview_token = draft_article.preview_token

      travel(Article::PREVIEW_TOKEN_EXPIRY + 1.minute) do
        get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: preview_token }
      end

      expect(response).to have_http_status(:not_found)
    end

    it 'skips portal analytics on a preview of an unpublished article' do
      portal.update!(config: portal.config.merge('analytics' => { 'ga4_measurement_id' => 'G-TEST123' }))
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: draft_article.preview_token }
      expect(response.body).not_to include('G-TEST123')

      get "/hc/#{portal.slug}/articles/#{article.slug}"
      expect(response.body).to include('G-TEST123')
    end

    it 'skips portal analytics on a preview link after the article is published' do
      portal.update!(config: portal.config.merge('analytics' => { 'ga4_measurement_id' => 'G-TEST123' }))

      get "/hc/#{portal.slug}/articles/#{article.slug}", params: { preview_token: article.preview_token }

      expect(response.body).not_to include('G-TEST123')
      expect(response.body).not_to include("/articles/#{article.slug}.png")
    end

    it 'skips noscript analytics on signed previews in both public layouts' do
      %w[classic documentation].each do |layout|
        analytics = { 'gtm_container_id' => 'GTM-PRIVATE', 'meta_pixel_id' => '987654321' }
        portal.update!(config: portal.config.merge('layout' => layout, 'analytics' => analytics))

        get "/hc/#{portal.slug}/articles/#{article.slug}", params: { preview_token: article.preview_token }

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('GTM-PRIVATE', '987654321')
      end
    end

    it 'treats a published article with an invalid preview token as a normal public page' do
      portal.update!(config: portal.config.merge('analytics' => { 'ga4_measurement_id' => 'G-TEST123' }))
      other_draft = create(:article, category: category, status: :draft, portal: portal, author: agent)

      ['junk', other_draft.preview_token].each do |preview_token|
        get "/hc/#{portal.slug}/articles/#{article.slug}", params: { preview_token: preview_token }

        expect(response.body).to include('G-TEST123')
        expect(response.headers['X-Robots-Tag']).to be_nil
      end
    end

    it 'marks a preview of an unpublished article as noindex' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: draft_article.preview_token }
      expect(response.headers['X-Robots-Tag']).to eq('noindex')

      get "/hc/#{portal.slug}/articles/#{article.slug}"
      expect(response.headers['X-Robots-Tag']).to be_nil
    end

    it 'skips the web widget on a preview of an unpublished article' do
      web_widget = create(:channel_widget, account: account)
      portal.update!(channel_web_widget: web_widget)
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: draft_article.preview_token }
      expect(response.body).not_to include(web_widget.website_token)

      get "/hc/#{portal.slug}/articles/#{article.slug}"
      expect(response.body).to include(web_widget.website_token)
    end

    it 'hides the article actions menu on a preview of an unpublished article' do
      portal.update!(config: portal.config.merge('layout' => 'documentation'))
      draft_article = create(:article, category: category, status: :draft, portal: portal, author: agent)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}", params: { preview_token: draft_article.preview_token }
      expect(response.body).not_to include(I18n.t('public_portal.article_actions.view_markdown'))

      get "/hc/#{portal.slug}/articles/#{article.slug}"
      expect(response.body).to include(I18n.t('public_portal.article_actions.view_markdown'))
    end

    it 'returns the article with the id with a different locale' do
      article_in_locale = create(:article, category: category_2, portal: portal, account_id: account.id, author_id: agent.id)
      get "/hc/#{portal.slug}/articles/#{article_in_locale.slug}"
      expect(response).to have_http_status(:success)
    end

    it 'keeps the locale switcher on the matching published translation' do
      translated_article = create(:article, category: category_2, portal: portal, account_id: account.id,
                                            author_id: agent.id, associated_article_id: article.id, status: :published)

      get "/hc/#{portal.slug}/articles/#{article.slug}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("value=\"/hc/#{portal.slug}/articles/#{translated_article.slug}\"")
    end

    it 'excludes unpublished translations from the locale switcher' do
      hidden_translation = create(:article, category: category_2, portal: portal, author: agent,
                                            associated_article_id: article.id, status: :draft)

      get "/hc/#{portal.slug}/articles/#{article.slug}"

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("/hc/#{portal.slug}/articles/#{hidden_translation.slug}")
    end

    it 'resolves the locale from the article itself for an uncategorized article' do
      uncategorized_article = create(:article, category: nil, locale: 'es', portal: portal,
                                               account_id: account.id, author_id: agent.id)
      get "/hc/#{portal.slug}/articles/#{uncategorized_article.slug}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('lang="es"')
    end
  end

  describe 'GET /public/api/v1/portals/:slug/articles/:slug.md (markdown)' do
    it 'serves the raw article markdown for a published article' do
      get "/hc/#{portal.slug}/articles/#{article.slug}.md"

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('text/markdown')
      expect(response.body).to eq(article.content)
    end

    it 'returns 404 for a draft article' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, account_id: account.id, author_id: agent.id)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}.md"

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 if the article does not exist' do
      get "/hc/#{portal.slug}/articles/non-existent-article.md"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /public/api/v1/portals/:slug/articles/:slug.png (tracking pixel)' do
    it 'serves a PNG image and increments view count for published article' do
      get "/hc/#{portal.slug}/articles/#{article.slug}.png"

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Cache-Control']).to include('max-age=86400')
      expect(response.headers['Cache-Control']).to include('private')
      expect(article.reload.views).to eq 1
    end

    it 'serves a PNG image but does not increment view count for draft article' do
      draft_article = create(:article, category: category, status: :draft, portal: portal, account_id: account.id, author_id: agent.id, views: 0)

      get "/hc/#{portal.slug}/articles/#{draft_article.slug}.png"

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Cache-Control']).to include('max-age=86400')
      expect(response.headers['Cache-Control']).to include('private')
      expect(draft_article.reload.views).to eq 0
    end

    it 'returns 404 if article does not exist' do
      get "/hc/#{portal.slug}/articles/non-existent-article.png"

      expect(response).to have_http_status(:not_found)
    end

    it 'sets proper cache headers for performance' do
      get "/hc/#{portal.slug}/articles/#{article.slug}.png"

      expect(response.headers['Cache-Control']).to include('max-age=86400')
      expect(response.headers['Cache-Control']).to include('private')
      expect(response.headers['Content-Type']).to eq('image/png')
    end
  end

  describe 'documentation layout sidebar for a region-variant locale' do
    let!(:th_portal) do
      create(:portal, slug: 'th-portal', custom_domain: 'th.example.com',
                      config: { allowed_locales: ['th_TH'], default_locale: 'th_TH', layout: 'documentation' })
    end
    let!(:th_category) do
      create(:category, name: 'TH Category', portal: th_portal, account_id: account.id, locale: 'th_TH', slug: 'th-cat')
    end
    let!(:th_article) do
      create(:article, category: th_category, portal: th_portal, account_id: account.id, author_id: agent.id, locale: 'th_TH')
    end

    before do
      create(:article, category: th_category, portal: th_portal, account_id: account.id, author_id: agent.id,
                       locale: 'th_TH', title: 'Sibling In Sidebar', status: :published)
    end

    it 'lists the category and sibling articles using the full portal locale' do
      host! 'th.example.com'
      get "/hc/#{th_portal.slug}/articles/#{th_article.slug}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Sibling In Sidebar')
    end
  end
end
