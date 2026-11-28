module TwilioMessagingSignatureVerification
  extend ActiveSupport::Concern
  include TwilioWebhookVerification

  included do
    before_action :verify_twilio_messaging_signature!
  end

  private

  # Observe messaging signatures without enabling enforcement during this rollout.
  def verify_twilio_messaging_signature!
    channel = twilio_channel
    return if channel.blank?
    return log_unverifiable_twilio_channel(channel) unless twilio_signature_verifiable?(channel)
    return if signed_by_twilio?(channel)

    Rails.logger.warn("[TWILIO] Invalid webhook signature channel_id=#{channel.id} endpoint=#{controller_name} enforced=false")
  end

  # API key channels store the key secret in auth_token, which Twilio does not sign with.
  def twilio_signature_verifiable?(channel)
    channel.api_key_sid.blank?
  end

  def signed_by_twilio?(channel)
    twilio_signature_urls.any? { |url| valid_twilio_signature?(channel.auth_token, url) }
  end

  def twilio_signature_urls
    registered_url = URI(twilio_webhook_url)
    registered_url.query = request.query_string.presence
    [request.original_url, registered_url.to_s].uniq
  end

  def log_unverifiable_twilio_channel(channel)
    Rails.logger.info("[TWILIO] Signature not verified, account auth token not configured channel_id=#{channel.id}")
  end
end
