# Fetches the bot's real Panel AI configuration (tools, integrations, inboxes)
# for the Bots tab preview — signed the same way as
# Calendar::NotifyPanelAiFollowupJob, so no Panel AI admin session is needed.
class PanelAi::AgentBotSummaryService
  def initialize(agent_bot)
    @agent_bot = agent_bot
  end

  def call
    base_url = ENV['PANEL_AI_URL'].to_s.chomp('/')
    return nil if base_url.blank?

    secret = ENV.fetch('PANEL_AI_WEBHOOK_SECRET', '')
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, '')}"

    response = HTTParty.get(
      "#{base_url}/api/inboxhub/agent-bots/#{@agent_bot.id}/summary",
      headers: { 'X-Panel-AI-Signature' => signature },
      timeout: 5
    )
    return nil unless response.success?

    response.parsed_response
  rescue StandardError => e
    Rails.logger.warn("[PanelAi::AgentBotSummaryService] #{e.class}: #{e.message}")
    nil
  end
end
