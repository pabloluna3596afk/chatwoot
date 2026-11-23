class Api::V1::Accounts::Integrations::CalendarTemplateDraftsController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_admin_authorization?

  def show
    render json: Calendar::TemplateDrafts::Provisioner.new(account: Current.account).status
  end

  def create
    render json: Calendar::TemplateDrafts::Provisioner.new(account: Current.account).perform
  end
end
