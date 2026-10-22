class Api::V1::Accounts::Integrations::CalendarActivationKitsController < Api::V1::Accounts::Integrations::BaseController
  wrap_parameters format: []

  before_action :check_admin_authorization?, only: :update

  def show
    render json: Calendar::ActivationKit.new(Current.account).status
  end

  def update
    inbox_ids = Array(params[:inbox_ids])
    render json: Calendar::ActivationKit.new(Current.account).apply(inbox_ids: inbox_ids)
  end
end
