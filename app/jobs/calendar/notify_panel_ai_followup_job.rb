class Calendar::NotifyPanelAiFollowupJob < ApplicationJob
  queue_as :default

  def perform(calendar_event_id, event_name = 'created')
    base_url = ENV['PANEL_AI_URL'].to_s.chomp('/')
    if base_url.blank?
      Rails.logger.warn('[Calendar::NotifyPanelAiFollowupJob] PANEL_AI_URL blank, skipping')
      return
    end

    record = CalendarEvent.find_by(id: calendar_event_id)
    return if record.blank?

    body = {
      event: event_name,
      calendar_event: {
        id: record.id,
        account_id: record.account_id,
        conversation_id: record.conversation_id,
        contact_id: record.contact_id,
        summary: record.summary,
        start_at: record.start_at&.iso8601,
        end_at: record.end_at&.iso8601,
        bot_followup_policy: record.bot_followup_policy,
        appointment_status: record.appointment_status
      }
    }.to_json

    secret = ENV.fetch('PANEL_AI_WEBHOOK_SECRET', '')
    headers = {
      'Content-Type' => 'application/json',
      'X-Panel-AI-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    }

    response = HTTParty.post(
      "#{base_url}/api/v1/inboxhub/calendar-events",
      headers: headers,
      body: body
    )
    return if response.success?

    Rails.logger.warn(
      "[Calendar::NotifyPanelAiFollowupJob] Panel AI responded #{response.code}: #{response.body}"
    )
  rescue StandardError => e
    Rails.logger.error("[Calendar::NotifyPanelAiFollowupJob] #{e.class}: #{e.message}")
  end
end
