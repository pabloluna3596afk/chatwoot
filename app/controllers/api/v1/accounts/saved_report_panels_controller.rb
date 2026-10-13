class Api::V1::Accounts::SavedReportPanelsController < Api::V1::Accounts::BaseController
  DETAIL_TABLE_KINDS = %w[conversations contacts].freeze

  rescue_from CustomExceptions::InvalidReportDateRange do |exception|
    render_could_not_create_error(exception.message)
  end

  before_action :check_authorization
  before_action :fetch_panel, only: [:show, :update, :destroy, :run, :export]
  before_action :validate_widget_configuration, only: [:create, :update, :preview]
  before_action :ensure_report_download_enabled, only: [:export]
  before_action :ensure_customer_data_download_enabled, only: [:export], if: :detail_tables?

  def index
    @panels = Current.account.saved_report_panels.ordered
  end

  def show; end

  def create
    @panel = Current.account.saved_report_panels.create!(
      panel_params.merge(created_by: Current.user)
    )
  end

  def update
    @panel.update!(panel_params)
  end

  def destroy
    @panel.destroy!
    head :no_content
  end

  def run
    render json: build_runner.perform
  end

  def preview
    @panel = SavedReportPanel.new(panel_params.merge(account: Current.account, created_by: Current.user))
    render json: build_runner.perform
  end

  def export
    result = build_runner.perform

    xlsx_data = Reports::PanelExportService.new(result).to_xlsx
    send_data xlsx_data,
              filename: ExportFilename.build(
                account: Current.account,
                resource: "panel-#{@panel.id}",
                extension: 'xlsx'
              ),
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  private

  def validate_widget_configuration
    candidate = SavedReportPanel.new(widgets: panel_params.fetch(:widgets) { @panel&.widgets || [] })
    candidate.validate_widget_configuration!
  end

  def build_runner
    Reports::PanelRunnerService.new(
      panel: @panel,
      account: Current.account,
      user: Current.user,
      timezone_offset: params[:timezone_offset],
      date_overrides: params.slice(:since, :until).to_unsafe_h.symbolize_keys
    )
  end

  def check_authorization
    authorize :report, :view?
  end

  # A panel with a table of conversations or contacts carries personal data (names, phones, emails, documents): its
  # export needs the customer-data download switch too, not only the one of aggregate reports.
  def detail_tables?
    Array(@panel.widgets).any? { |widget| DETAIL_TABLE_KINDS.include?(widget.with_indifferent_access[:table_kind].to_s) }
  end

  def fetch_panel
    @panel = Current.account.saved_report_panels.find(params[:id])
  end

  def panel_params
    raw = params.require(:saved_report_panel)
    attrs = {}
    attrs[:name] = raw[:name] if raw.key?(:name)
    attrs[:description] = raw[:description] if raw.key?(:description)
    attrs[:date_preset] = raw[:date_preset] if raw.key?(:date_preset)
    attrs[:custom_since] = cast_unix(raw[:custom_since]) if raw.key?(:custom_since)
    attrs[:custom_until] = cast_unix(raw[:custom_until]) if raw.key?(:custom_until)
    attrs[:date_attribute] = raw[:date_attribute].to_s if raw.key?(:date_attribute)
    attrs[:filters] = normalize_json_array(raw[:filters]) if raw.key?(:filters)
    attrs[:widgets] = normalize_json_array(raw[:widgets]) if raw.key?(:widgets)
    attrs[:business_hours] = ActiveModel::Type::Boolean.new.cast(raw[:business_hours]) if raw.key?(:business_hours)
    attrs[:favorite] = ActiveModel::Type::Boolean.new.cast(raw[:favorite]) if raw.key?(:favorite)
    attrs
  end

  def cast_unix(value)
    return nil if value.blank?

    value.to_i
  end

  def normalize_json_array(value)
    return [] if value.nil?

    Array(value).filter_map do |item|
      next item if item.is_a?(Hash)
      next item.to_unsafe_h if item.respond_to?(:to_unsafe_h)
      next item.to_h if item.respond_to?(:to_h)

      nil
    end
  end
end
