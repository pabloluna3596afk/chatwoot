class Captain::AssistantPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.for_account(account.id).customer_visible
    end
  end

  def index?
    true
  end

  def show?
    true
  end

  def metrics?
    true
  end

  def faq_stats?
    true
  end

  def summary?
    true
  end

  def drilldown?
    @account_user.administrator?
  end

  def tools?
    @account_user.administrator? || account.feature_enabled?('captain_integration_v2')
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator? && (record.is_a?(Class) || !record.internal?)
  end

  def approve?
    update?
  end

  def dismiss?
    update?
  end

  def destroy?
    @account_user.administrator? && (record.is_a?(Class) || !record.internal?)
  end

  def avatar?
    update?
  end

  def sync?
    @account_user.administrator?
  end

  def playground?
    true
  end

  def playground_usage?
    true
  end
end
