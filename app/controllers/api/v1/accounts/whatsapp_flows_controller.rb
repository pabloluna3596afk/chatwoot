# The forms ("flows") built in ChatHub: saved as drafts in the neutral format of Whatsapp::Flows::Spec, checked and exported
# to Meta's Flow JSON. Everyone in the account can read them; only administrators create, change, delete or check them.
class Api::V1::Accounts::WhatsappFlowsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index, :show]
  before_action :fetch_flow, only: [:show, :update, :destroy, :duplicate, :publish, :publication_status, :test, :retry_publish]
  before_action :validate_catalog_filters, only: [:index, :publication_status]

  LIST_STATES = %w[published partial error none].freeze
  DETAIL_STATES = %w[published error none draft deprecated blocked throttled].freeze
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  def index
    catalog = Whatsapp::Flows::PublicationCatalog.new(Current.account)
    flows = catalog.filter_flows(search: params[:search], category: params[:category], state: params[:state])
    total = flows.count(:all)
    page = catalog_page
    per_page = catalog_per_page
    rows = flows.order(updated_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)
    payload = rows.map { |flow| summary(flow, unpublished: flow.catalog_unpublished).merge(publication_summary: catalog.summary(flow)) }
    facets = catalog.facets(search: params[:search], category: params[:category], state: params[:state])
    render json: { payload: payload, meta: { current_page: page, per_page: per_page, total_count: total }, facets: facets }
  end

  def show
    render json: detail(@flow)
  end

  def create
    flow = Current.account.whatsapp_flows.new(flow_params.merge(created_by: Current.user))
    return render_errors(flow) unless flow.save

    render json: detail(flow), status: :created
  end

  def update
    return render_errors(@flow) unless @flow.update(flow_params)

    render json: detail(@flow)
  end

  def duplicate
    flow = Current.account.whatsapp_flows.new(
      name: "#{@flow.name.first(92)} (copia)", definition: @flow.definition.deep_dup,
      categories: @flow.categories.dup, created_by: Current.user
    )
    return render_errors(flow) unless flow.save

    render json: detail(flow), status: :created
  end

  def destroy
    @flow.destroy!
    head :no_content
  end

  # Checks a definition that is still being edited (nothing is saved): the mistakes Meta would refuse and, when there are
  # none, the Flow JSON it becomes.
  def validate
    definition = params[:definition].respond_to?(:to_unsafe_h) ? params[:definition].to_unsafe_h : {}
    result = Whatsapp::Flows::DefinitionValidator.new(definition, account: Current.account).call
    render json: { valid: result.valid?, errors: result.errors, warnings: result.warnings, flow_json: result.valid? ? export(definition) : nil }
  end

  # Sends the flow to Meta on every WhatsApp Cloud WABA of the account, in the background; the dashboard polls
  # publication_status for the per-WABA result.
  def publish
    return render json: { error: 'no_cloud_channels' }, status: :unprocessable_entity if cloud_channels.empty?

    Whatsapp::PublishFlowToMetaJob.perform_later(@flow.id, Current.account.id)
    render json: publication_payload, status: :accepted
  end

  def publication_status
    if params.key?(:page)
      catalog = Whatsapp::Flows::PublicationCatalog.new(Current.account)
      render json: catalog.detail(@flow, page: catalog_page, per_page: catalog_per_page, search: params[:search], state: params[:state])
    else
      render json: publication_payload
    end
  end

  # "Probar": sends the flow to a phone number through one Cloud channel without publishing it.
  def test
    channel = cloud_channels.find { |candidate| candidate.id == params.require(:channel_id).to_i }
    return render json: { success: false, error: 'channel_not_found' }, status: :not_found if channel.nil?

    result = Whatsapp::Flows::TestFlowService.new(@flow, channel, params.require(:phone_number)).perform
    render json: result, status: result[:success] ? :ok : :unprocessable_entity
  end

  def retry_publish
    publication = @flow.whatsapp_flow_publications.find_by!(waba_id: params[:waba_id])
    Whatsapp::PublishFlowToMetaJob.perform_later(@flow.id, Current.account.id, publication.waba_id)
    render json: publication_payload, status: :accepted
  end

  private

  def validate_catalog_filters
    invalid = params.slice(:page, :per_page, :search, :state, :category).each_pair.any? { |key, value| !valid_catalog_filter?(key, value) }
    render json: { error: 'invalid', message: 'Invalid catalog filters' }, status: :unprocessable_entity if invalid
  end

  def valid_catalog_filter?(key, value)
    return false unless value.is_a?(String)

    case key
    when 'page', 'per_page' then valid_catalog_page?(key, value)
    when 'search' then value.length <= 200
    when 'state' then (action_name == 'index' ? LIST_STATES : DETAIL_STATES).include?(value)
    when 'category' then Whatsapp::Flows::Spec::CATEGORIES.include?(value)
    end
  end

  def valid_catalog_page?(key, value)
    value.match?(/\A[1-9]\d*\z/) && (key == 'page' || value.to_i <= MAX_PER_PAGE)
  end

  def catalog_page
    params.fetch(:page, '1').to_i
  end

  def catalog_per_page
    params.fetch(:per_page, DEFAULT_PER_PAGE.to_s).to_i
  end

  def cloud_channels
    @cloud_channels ||= Whatsapp::Flows::CloudChannels.for(Current.account)
  end

  def publication_payload
    publications = @flow.whatsapp_flow_publications.order(:waba_id).map do |publication|
      publication.slice(:waba_id, :status, :meta_flow_id, :validation_errors, :published_version, :published_at)
    end
    wabas = cloud_channels.map do |channel|
      { waba_id: channel.provider_config['business_account_id'], channel_id: channel.id, phone_number: channel.phone_number,
        inbox_name: channel.inbox&.name }
    end
    { flow_id: @flow.id, wabas: wabas, publications: publications, unpublished_changes: unpublished_changes?(@flow) }
  end

  def fetch_flow
    @flow = Current.account.whatsapp_flows.find(params[:id])
  end

  def flow_params
    attributes = params.require(:whatsapp_flow).permit(:name, categories: [])
    definition = params[:whatsapp_flow][:definition]
    attributes[:definition] = definition.to_unsafe_h if definition.respond_to?(:to_unsafe_h)
    attributes
  end

  def export(definition)
    Whatsapp::Flows::Exporter.new(definition).call
  end

  def summary(flow, unpublished: unpublished_changes?(flow))
    { id: flow.id, name: flow.name, categories: flow.categories, screens: flow.definition['screens'].to_a.size,
      updated_at: flow.updated_at.to_i, created_at: flow.created_at.to_i,
      unpublished_changes: unpublished }
  end

  def unpublished_changes?(flow)
    flow.whatsapp_flow_publications.any? do |publication|
      publication.published_at.present? && publication.published_at < flow.updated_at
    end
  end

  def detail(flow)
    summary(flow).merge(definition: flow.definition)
  end

  def render_errors(flow)
    render json: { error: 'invalid', message: flow.errors.full_messages.to_sentence, details: flow.errors.to_hash }, status: :unprocessable_entity
  end
end
