class Api::V1::Accounts::Integrations::CalendarActivationKitsController < Api::V1::Accounts::Integrations::BaseController
  wrap_parameters format: []

  before_action :check_admin_authorization?, only: :update

  def show
    render json: Calendar::ActivationKit.new(Current.account).status
  end

  def update
    if params.key?(:reminder_enabled)
      unless [true, false].include?(params[:reminder_enabled])
        return render json: { error: 'reminder_enabled must be a boolean' }, status: :unprocessable_entity
      end

      Current.account.update!(customer_reminders_enabled: params[:reminder_enabled])
      return render json: Calendar::ActivationKit.new(Current.account).status
    end

    inbox_ids = Array(params[:inbox_ids])
    render json: Calendar::ActivationKit.new(Current.account).apply(inbox_ids: inbox_ids)
  end
end
