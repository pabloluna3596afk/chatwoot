class Api::V1::Accounts::BackgroundTasksController < Api::V1::Accounts::BaseController
  def index
    render json: BackgroundTasks::Sources.tasks(Current.account, Current.user)
  end
end
