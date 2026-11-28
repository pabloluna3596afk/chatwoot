module InboxBotStatus
  extend ActiveSupport::Concern

  def active_bot?
    external_bot_active?
  end

  def external_bot_active?
    agent_bot_inbox&.active? || dialogflow_active?
  end

  private

  def dialogflow_active?
    hooks.exists?(account_id: account_id, app_id: %w[dialogflow], status: 'enabled')
  end
end
