class Api::V1::Accounts::Integrations::CalendarAppointmentAttributesController < Api::V1::Accounts::Integrations::BaseController
  wrap_parameters format: []

  before_action :check_admin_authorization?, only: :update

  def show
    render json: Calendar::AppointmentAttributes::Provisioner.new(account: Current.account).status
  end

  def update
    keys = params[:keys]
    valid = keys.is_a?(Array) && keys.all? { |key| key.is_a?(String) && Calendar::AppointmentAttributes::Definitions::TYPES.key?(key) }
    unless valid && keys.uniq == keys
      return render json: { error: I18n.t('integration_apps.calendars.appointment_attributes.invalid_keys') }, status: :unprocessable_entity
    end

    render json: Calendar::AppointmentAttributes::Provisioner.new(account: Current.account).perform(keys: keys)
  end
end
