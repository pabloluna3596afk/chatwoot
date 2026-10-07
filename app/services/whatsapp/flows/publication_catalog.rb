# Local publication state, grouped by WABA. No provider credentials or Meta requests are needed to browse it.
class Whatsapp::Flows::PublicationCatalog
  ERROR_STATES = %w[error blocked throttled].freeze
  CHANNEL_WABA = "channel_whatsapp.provider_config->>'business_account_id'".freeze
  PUBLICATION_ERROR = "status IN ('blocked', 'throttled') OR (status IN ('draft', 'published') AND validation_errors <> '[]'::jsonb)".freeze

  def initialize(account)
    @account = account
    @channels = account.whatsapp_channels.where(provider: 'whatsapp_cloud')
                       .where("#{CHANNEL_WABA} IS NOT NULL AND #{CHANNEL_WABA} <> ''")
    @waba_ids = @channels.distinct.pluck(Arel.sql(CHANNEL_WABA))
  end

  def flows
    published_count = "COUNT(*) FILTER (WHERE status = 'published' AND validation_errors = '[]'::jsonb) AS published"
    counts = WhatsappFlowPublication.where(account_id: @account.id, waba_id: @waba_ids).group(:whatsapp_flow_id)
                                    .select(:whatsapp_flow_id, Arel.sql(published_count),
                                            Arel.sql("COUNT(*) FILTER (WHERE #{PUBLICATION_ERROR}) AS errors"))
    @account.whatsapp_flows
            .joins("LEFT JOIN (#{counts.to_sql}) publication_counts ON publication_counts.whatsapp_flow_id = whatsapp_flows.id")
            .select('whatsapp_flows.*', 'COALESCE(publication_counts.published, 0) AS catalog_published',
                    'COALESCE(publication_counts.errors, 0) AS catalog_errors', "#{summary_state} AS catalog_state",
                    'EXISTS (SELECT 1 FROM whatsapp_flow_publications p WHERE p.whatsapp_flow_id = whatsapp_flows.id ' \
                    'AND p.published_at < whatsapp_flows.updated_at) AS catalog_unpublished')
  end

  def filter_state(scope, state)
    scope.where("#{summary_state} = ?", state)
  end

  def filter_flows(search: nil, category: nil, state: nil)
    scope = flows
    scope = scope.where('whatsapp_flows.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(search)}%") if search.present?
    scope = scope.where('categories @> ?::jsonb', [category].to_json) if category.present?
    state.present? ? filter_state(scope, state) : scope
  end

  def summary(flow)
    { state: flow.catalog_state, total: @waba_ids.length, published: flow.catalog_published, errors: flow.catalog_errors }
  end

  # Each facet keeps the search and the other facet, but ignores its own selection.
  # Aggregates run in SQL over the whole catalog, before pagination.
  def facets(search: nil, category: nil, state: nil)
    states = filter_flows(search: search, category: category).unscope(:select)
    state_counts = states.group(Arel.sql(summary_state)).count(:all)
    categories = filter_flows(search: search, state: state).unscope(:select)
    category_counts = categories
                      .joins('CROSS JOIN LATERAL jsonb_array_elements_text(whatsapp_flows.categories) AS facet_categories(value)')
                      .group('facet_categories.value').count(Arel.sql('DISTINCT whatsapp_flows.id'))
    { state: { 'all' => state_counts.values.sum }.merge(%w[published partial error none].index_with { |value| state_counts.fetch(value, 0) }),
      category: { 'all' => categories.count(:all) }.merge(Whatsapp::Flows::Spec::CATEGORIES.index_with { |value| category_counts.fetch(value, 0) }) }
  end

  def detail(flow, page:, per_page:, search: nil, state: nil)
    scope, row_state = waba_rows(flow)
    if search.present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
      scope = scope.where('flow_wabas.waba_id ILIKE ? OR flow_wabas.numbers::text ILIKE ?', query, query)
    end
    scope = scope.where("#{row_state} IN (?)", state == 'error' ? ERROR_STATES : [state]) if state.present?
    total = scope.count(:all)
    rows = scope.select('flow_wabas.*', "#{row_state} AS state", 'publications.meta_flow_id',
                        "COALESCE(publications.validation_errors, '[]'::jsonb) AS validation_errors")
                .order(Arel.sql("CASE WHEN #{row_state} IN ('error', 'blocked', 'throttled') THEN 0 ELSE 1 END, flow_wabas.waba_id"))
                .offset((page - 1) * per_page).limit(per_page)
                .map { |row| row.attributes.slice('waba_id', 'numbers', 'state', 'meta_flow_id', 'validation_errors') }
    entry = flows.find(flow.id)
    { flow_id: flow.id, rows: rows, publication_summary: summary(entry), unpublished_changes: entry.catalog_unpublished,
      meta: { current_page: page, per_page: per_page, total_count: total } }
  end

  private

  def waba_rows(flow)
    numbers = "jsonb_agg(jsonb_build_object('channel_id', channel_whatsapp.id, 'phone_number', channel_whatsapp.phone_number, " \
              "'inbox_name', inboxes.name) ORDER BY channel_whatsapp.id) AS numbers"
    wabas = @channels.left_joins(:inbox).group(Arel.sql(CHANNEL_WABA)).select("#{CHANNEL_WABA} AS waba_id", numbers)
    row_state = "CASE WHEN publications.status IN ('draft', 'published') AND publications.validation_errors <> '[]'::jsonb " \
                "THEN 'error' ELSE COALESCE(publications.status, 'none') END"
    scope = Channel::Whatsapp.from("(#{wabas.to_sql}) flow_wabas")
                             .joins('LEFT JOIN whatsapp_flow_publications publications ON publications.waba_id = flow_wabas.waba_id ' \
                                    "AND publications.whatsapp_flow_id = #{flow.id}")
    [scope, row_state]
  end

  def summary_state
    "CASE WHEN COALESCE(publication_counts.errors, 0) > 0 THEN 'error' " \
      "WHEN #{@waba_ids.length} > 0 AND COALESCE(publication_counts.published, 0) = #{@waba_ids.length} THEN 'published' " \
      "WHEN COALESCE(publication_counts.published, 0) > 0 THEN 'partial' ELSE 'none' END"
  end
end
