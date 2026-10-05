# The forms ("flows") built in ChatHub: saved as drafts in the neutral format of Whatsapp::Flows::Spec, checked and exported
# to Meta's Flow JSON. Everyone in the account can read them; only administrators create, change, delete or check them.
class Api::V1::Accounts::WhatsappFlowsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index, :show]
  before_action :fetch_flow, only: [:show, :update, :destroy]

  def index
    render json: { payload: Current.account.whatsapp_flows.order(updated_at: :desc).map { |flow| summary(flow) } }
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

  def destroy
    @flow.destroy!
    head :no_content
  end

  # Checks a definition that is still being edited (nothing is saved): the mistakes Meta would refuse and, when there are
  # none, the Flow JSON it becomes.
  def validate
    definition = params[:definition].respond_to?(:to_unsafe_h) ? params[:definition].to_unsafe_h : {}
    result = Whatsapp::Flows::DefinitionValidator.new(definition).call
    render json: { valid: result.valid?, errors: result.errors, warnings: result.warnings, flow_json: result.valid? ? export(definition) : nil }
  end

  private

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

  def summary(flow)
    { id: flow.id, name: flow.name, categories: flow.categories, screens: flow.definition['screens'].to_a.size,
      updated_at: flow.updated_at.to_i, created_at: flow.created_at.to_i }
  end

  def detail(flow)
    summary(flow).merge(definition: flow.definition)
  end

  def render_errors(flow)
    render json: { error: 'invalid', message: flow.errors.full_messages.to_sentence, details: flow.errors.to_hash }, status: :unprocessable_entity
  end
end
