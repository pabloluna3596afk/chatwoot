class Api::V1::Accounts::Captain::DocumentsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_current_page, only: [:index]
  before_action :set_documents, except: [:create, :estimate]
  before_action :set_document, only: [:show, :destroy, :sync, :resume, :drilldown]
  before_action :set_assistant, only: [:create]
  RESULTS_PER_PAGE = 25

  def index
    documents = filtered_documents
    @documents_count = documents.count
    @sync_interval_hours = current_sync_interval&.in_hours&.to_i
    @documents = apply_sort(documents, permitted_params[:sort])
    @documents = with_responses_count(@documents).page(@current_page).per(RESULTS_PER_PAGE)
    return unless can_view_drilldown?

    @document_usage_counts = Captain::ConversationUsageBuilder.conversation_counts(@documents, usage_column: :document_ids)
  end

  def show; end

  def estimate
    input = params.permit(:pdf_file, :external_link)
    if input.key?(:pdf_file) == input.key?(:external_link) || (input.key?(:external_link) && !valid_external_link?(input[:external_link]))
      return render_could_not_create_error(I18n.t('captain.contracts.invalid_url'))
    end
    return render_could_not_create_error(I18n.t('captain.documents.pdf_format_error')) if input.key?(:pdf_file) && input[:pdf_file].nil?

    render json: Captain::Documents::UsageEstimate.for_upload(account: Current.account, pdf_file: input[:pdf_file])
  rescue CustomExceptions::Pdf::ValidationError => e
    render_could_not_create_error(e.message)
  end

  def resume
    @document.with_lock do
      unless @document.last_sync_error_code == 'usage_quota_exceeded'
        return render_could_not_create_error(I18n.t('captain.documents.resume_not_pending'))
      end

      units = @document.pdf_document? ? Llm::UnitCosts.fetch(:pdf, :units_per_chunk) : Llm::UnitCosts.text_units(@document.content.length)
      estimate = Captain::Documents::UsageEstimate.for_units(account: Current.account, units: units)
      return render_could_not_create_error(I18n.t('captain.documents.usage_quota_exceeded')) unless estimate[:sufficient]

      @document.update!(last_sync_error_code: nil)
      Captain::Documents::ResponseBuilderJob.perform_later(@document)
    end
    head :accepted
  end

  def create
    return render_could_not_create_error('Missing Assistant') if @assistant.nil?

    if document_params.key?(:external_link) && !valid_external_link?(document_params[:external_link])
      return render_could_not_create_error(I18n.t('captain.contracts.invalid_url'))
    end

    ensure_upload_quota!
    @document = @assistant.documents.build(document_params)
    @document.save!
  rescue Captain::Document::LimitExceededError, CustomExceptions::Pdf::ValidationError => e
    render_could_not_create_error(e.message)
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages.join(', '))
  end

  def sync
    return render_could_not_create_error(I18n.t('captain.documents.sync_not_supported_for_file')) unless @document.syncable?
    return render_could_not_create_error(I18n.t('captain.documents.sync_only_available_documents')) unless @document.available?

    @document.update!(
      sync_status: :syncing,
      sync_step: nil,
      last_sync_error_code: nil,
      last_sync_attempted_at: Time.current
    )
    Captain::Documents::PerformSyncJob.perform_later(@document)
    head :accepted
  end

  def drilldown
    render json: Captain::ConversationUsageBuilder.new(@document, drilldown_params, usage_column: :document_ids).build
  end

  def destroy
    @document.destroy
    head :no_content
  end

  private

  def ensure_upload_quota!
    return unless document_params[:pdf_file] || document_params[:external_link]

    estimate = Captain::Documents::UsageEstimate.for_upload(account: Current.account, pdf_file: document_params[:pdf_file])
    raise Captain::Document::LimitExceededError, I18n.t('captain.documents.usage_quota_exceeded') unless estimate[:sufficient]
  end

  def valid_external_link?(value)
    return false unless value.is_a?(String)

    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def set_documents
    @documents = Current.account.captain_documents.with_attached_pdf_file.with_attached_markdown_file
                        .includes(assistant: { avatar_attachment: :blob })
  end

  def filtered_documents
    documents = @documents
    documents = documents.where(assistant_id: permitted_params[:assistant_id]) if permitted_params[:assistant_id].present?
    documents = apply_source_filter(documents, permitted_params[:source])
    documents = apply_filter(documents, permitted_params[:filter])
    apply_search(documents, permitted_params[:search_key])
  end

  def with_responses_count(scope)
    scope.left_joins(:responses)
         .select('captain_documents.*, COUNT(captain_assistant_responses.id) AS responses_count')
         .group('captain_documents.id')
  end

  def set_document
    @document = @documents.find(permitted_params[:id])
  end

  def set_assistant
    @assistant = Current.account.captain_assistants.find_by(id: document_params[:assistant_id])
  end

  def set_current_page
    @current_page = permitted_params[:page] || 1
  end

  def permitted_params
    params.permit(:assistant_id, :page, :id, :account_id, :filter, :source, :sort, :search_key)
  end

  def drilldown_params
    params.permit(:page, :per_page)
  end

  def can_view_drilldown?
    policy(Captain::Assistant).drilldown?
  end

  def apply_source_filter(scope, source)
    case source
    when 'web' then scope.syncable
    when 'pdf' then scope.pdf_documents
    else scope
    end
  end

  def apply_filter(scope, filter)
    case filter
    when 'stale' then stale_documents(scope.syncable)
    when 'synced' then up_to_date_documents(scope.syncable)
    when 'syncing' then scope.syncable.sync_in_progress
    when 'failed' then scope.syncable.sync_failed
    else scope
    end
  end

  def apply_search(scope, search_key)
    return scope if search_key.blank?

    query = "%#{ActiveRecord::Base.sanitize_sql_like(search_key)}%"
    scope.where('captain_documents.name ILIKE :query OR captain_documents.external_link ILIKE :query', query: query)
  end

  def apply_sort(scope, sort)
    case sort
    when 'recently_created' then scope.order(created_at: :desc)
    when 'most_used'
      authorize(Captain::Assistant, :drilldown?)
      Captain::ConversationUsageBuilder.order_documents_by_conversation_count(
        scope,
        account_id: Current.account.id,
        assistant_id: permitted_params[:assistant_id]
      )
    else scope.order(updated_at: :desc)
    end
  end

  def stale_documents(scope)
    return scope.none unless current_sync_interval

    scope.sync_synced.where(Captain::Document.arel_table[:last_synced_at].lt(current_sync_interval.ago))
  end

  def up_to_date_documents(scope)
    documents = scope.sync_synced
    return documents unless current_sync_interval

    documents.where(Captain::Document.arel_table[:last_synced_at].gteq(current_sync_interval.ago))
  end

  def current_sync_interval
    return @current_sync_interval if defined?(@current_sync_interval)

    @current_sync_interval = Current.account.captain_document_sync_interval
  end

  def document_params
    params.require(:document).permit(:name, :external_link, :assistant_id, :pdf_file, :markdown_content)
  end
end
