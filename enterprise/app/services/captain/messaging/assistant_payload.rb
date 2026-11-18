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
      availability = Captain::Messaging::Availability.new(@assistant, inbox, request_cache: request_cache)
      items = availability.templates + availability.flows
      states = STATES.index_with { |state| items.count { |item| item.state == state } }
      {
        inbox_id: inbox.id,
        mode: @assistant.messaging.mode(inbox.id),
        waba_id: inbox.channel.is_a?(Channel::Whatsapp) ? inbox.channel.provider_config.to_h['business_account_id'] : nil,
        resources: items.map { |item| item_payload(item) },
        counts: states,
        scope: scope_note(inbox)
      }
    end
  end

  def item_payload(item)
    {
      resource: item.resource,
      state: item.state,
      note: item.note,
      missing: item.missing,
      can_send: item.available?,
      reason: item.reason
    }.compact
  end

  def scope_note(inbox)
    return 'WhatsApp templates and Flows are unavailable for this channel.' unless inbox.channel_type == 'Channel::Whatsapp'

    'WhatsApp resources are scoped to this inbox and its connected WABA.'
  end
end
