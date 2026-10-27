class Api::V1::Accounts::Captain::CopilotActionItemsController < Api::V1::Accounts::BaseController
  before_action :ensure_captain_integration_enabled
  before_action :set_thread
  before_action :set_action_item, only: [:update, :approve, :reject]

  def index
    @items = @thread.copilot_action_items.order(:created_at)
    @items.each(&:expire_if_needed!)
    render json: @items.map(&:push_event_data)
  end

  def update
    item = service.update(item: @action_item, payload: permitted_payload.to_h)
    return render json: item.push_event_data, status: :gone if item.status == 'expired'

    render json: item.push_event_data
  rescue Captain::Copilot::ActionItemService::ExpiredError => e
    render json: { error: e.message }, status: :gone
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def approve
    item = service.decide(item: @action_item, decision: 'approve')
    return render json: item.push_event_data, status: :gone if item.status == 'expired'

    render json: item.push_event_data
  rescue Captain::Copilot::ActionItemService::ExpiredError => e
    render json: @action_item.push_event_data.merge(error: e.message), status: :gone
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reject
    item = service.decide(item: @action_item, decision: 'reject')
    return render json: item.push_event_data, status: :gone if item.status == 'expired'

    render json: item.push_event_data
  rescue Captain::Copilot::ActionItemService::ExpiredError => e
    render json: { error: e.message }, status: :gone
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_thread
    @thread = Current.account.copilot_threads.find_by!(id: params[:copilot_thread_id], user: Current.user)
  end

  def set_action_item
    @action_item = @thread.copilot_action_items.find(params[:id])
  end

  def service
    @service ||= Captain::Copilot::ActionItemService.new(thread: @thread, user: Current.user)
  end

  def permitted_payload
    params.require(:payload).permit!.to_h
  end

  def ensure_captain_integration_enabled
    return if Current.account.feature_enabled?('captain_integration')

    render json: { error: 'Captain integration is not enabled for this account' }, status: :forbidden
  end
end
