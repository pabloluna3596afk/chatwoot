module InternalTasksFeatureEnabled
  extend ActiveSupport::Concern

  included do
    before_action :ensure_internal_tasks_enabled
  end

  private

  def ensure_internal_tasks_enabled
    return if Current.account.feature_enabled?('internal_tasks')

    render json: { error: 'Feature not enabled' }, status: :forbidden
  end
end
