class Captain::Messaging::AssistantPayload
  STATES = %w[
    available new changed needs_review needs_data pending rejected unsupported excluded marketing_off authentication
    not_published_here disabled unavailable
  ].freeze

  def initialize(assistant)
    @assistant = assistant
  end

  def as_json
    cap = Captain::TemplateDailyCap.new(@assistant.account)
    {
      inboxes: inbox_payloads,
      template_cap: { cap: cap.daily_cap, used: cap.used }
    }
  end

  private

  def inbox_payloads
    request_cache = {}
    @assistant.captain_inboxes.includes(inbox: :channel).map do |link|
      inbox = link.inbox
      inbox_payload(inbox, request_cache)
    end
  end

  def inbox_payload(inbox, request_cache)
    items = available_items(inbox, request_cache)
    { inbox_id: inbox.id, mode: @assistant.messaging.mode(inbox.id),
      waba_id: waba_id(inbox), resources: items.map { |item| item_payload(item) },
      counts: state_counts(items), scope: scope_note(inbox), channel: channel_payload(inbox) }
  end

  def available_items(inbox, request_cache)
    availability = Captain::Messaging::Availability.new(@assistant, inbox, request_cache: request_cache)
    availability.templates.select { |item| item.resource['category'].to_s.upcase == 'UTILITY' } + availability.flows
  end

  def state_counts(items)
    STATES.index_with { |state| items.count { |item| item.state == state } }
  end

  def waba_id(inbox)
    inbox.channel.is_a?(Channel::Whatsapp) ? inbox.channel.provider_config.to_h['business_account_id'] : nil
  end

  def item_payload(item)
    {
      resource: item.resource,
      state: item.state,
      note: item.note,
      missing: item.missing,
      processed_params: item.processed_params,
      sources: item.sources,
      can_send: item.available?,
      reason: item.reason
    }.compact
  end

  def scope_note(inbox)
    return 'WhatsApp templates and Flows are unavailable for this channel.' unless inbox.channel_type == 'Channel::Whatsapp'

    'WhatsApp resources are scoped to this inbox and its connected WABA.'
  end

  def channel_payload(inbox)
    return {} unless inbox.channel_type == 'Channel::Whatsapp'

    channel = inbox.channel
    health = channel.phone_number_health.to_h
    {
      business_account_name: health['business_account_name'],
      business_portfolio_name: health['business_portfolio_name'],
      quality_rating: health['quality_rating'],
      templates_last_updated_at: channel.message_templates_last_updated&.iso8601,
      templates_stale: channel.message_templates_last_updated.nil? || channel.message_templates_last_updated < 48.hours.ago,
      needs_reauthorization: channel.reauthorization_required?
    }.compact
  end
end
