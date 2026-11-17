class Captain::Capabilities::Base
  STATUSES = %w[ready needs_setup not_connected off].freeze
  REASONS = %w[
    templates_off disabled no_template template_unavailable no_calendar_selected no_items
    not_connected_whatsapp not_connected_calendar window_only
  ].freeze

  def self.inboxes_for(assistant)
    assistant.captain_inboxes.includes(:inbox).map(&:inbox)
  end

  def self.whatsapp_inboxes_for(assistant)
    Captain::Capabilities::Base.inboxes_for(assistant).select { |inbox| inbox.channel_type == 'Channel::Whatsapp' }
  end

  def initialize(assistant, inbox = nil)
    @assistant = assistant
    @inbox = inbox
  end

  private

  attr_reader :assistant, :inbox

  def result(status, reason = nil, count = nil)
    raise ArgumentError, "Invalid capability status: #{status}" if STATUSES.exclude?(status)
    raise ArgumentError, "Invalid capability reason: #{reason}" if reason && REASONS.exclude?(reason)

    { status: status, reason: reason, count: count }
  end

  def whatsapp_inboxes
    return [inbox] if inbox&.channel_type == 'Channel::Whatsapp'

    @whatsapp_inboxes ||= assistant.captain_inboxes.includes(:inbox).filter_map do |link|
      link.inbox if link.inbox.channel_type == 'Channel::Whatsapp'
    end
  end

  def configured_entry
    Array(assistant.config.dig('messaging', 'inboxes')).find do |entry|
      entry.is_a?(Hash) && entry['inbox_id'] == inbox&.id
    end
  end
end
